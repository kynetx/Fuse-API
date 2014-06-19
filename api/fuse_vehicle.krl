ruleset fuse_vehicle {
    meta {
      name "Fuse API for Vehicle"
      description <<
Fuse ruleset for a vehicle pico
    >>
      author "PJW"
      logging off
      sharing on

      errors to b16x13

      use module b16x10 alias fuse_keys

      use module a169x625 alias CloudOS
      use module a169x676 alias pds
      use module b16x11 alias carvoyant
      use module b16x19 alias common
      // don't load trips
	
      provides vin, fleetChannel, vehicleSummary, lastTrip, vehicleSubscription

    }

    global {

      fleetChannel = function () {
          CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.eventChannel");
      };

      myIncomingChannel = function () {
          CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.backChannel");
      };

      vin = function() {
        this_vin = vehicle_info().pick("$.vin");

        (this_vin.isnull()) => "NO_VIN" | this_vin
      };

      vehicleSummary = function(){
        pds:get_item(carvoyant:namespace(), "vehicle_info");
      }

      lastTrip = function(key) {
        trip = pds:get_item(carvoyant:namespace(), "last_trip_info");
	key => trip{key}
             | trip
      }

      vehicleStatus = function(key) {
        status = pds:get_item(carvoyant:namespace(), "vehicle_status");
	key => status{key} 
             | status
      }

      // subscription_type is optional, if left off, retrieves all subscriptions for vehicle
      // subscription_id is optional, if left off, retrieves all subscriptions of given type
      vehicleSubscription = function(subscription_type, subscription_id) {
        vid = carvoyant:vehicle_id();
        raw_result = carvoyant:getSubscription(vid, subscription_type, subscription_id);
	raw_result{"status_code"} eq "200" => raw_result{"content"}.decode().pick("$.subscriptions")
                                            | raw_result
      }

    }

    // ---------- initialization ----------
    rule setup_vehicle_pico {
        select when fuse new_vehicle

	pre {
	   name = event:attr("name");
	   photo = event:attr("photo");
           my_fleet = event:attr("fleet_channel");
           my_schema = event:attr("schema");
	   device_id = event:attr("deviceId");
	   vin = event:attr("vin");

	   // need to take stuff from event attrs and fill our schema

	}

        {
            send_directive("initializing vehicle pico")
	      with name = name;
        }

        fired {

	  log ">>>>>>>>>>>>>>>>> initialize_vehicle_pico <<<<<<<<<<<<<<<<<<<<";

	  // store meta info
	  raise pds event new_map_available 
            attributes 
              {"namespace": common:namespace(),
               "mapvalues": {"schema": my_schema,
	                     "fleet_channel": my_fleet,
			     "vehicle_name": name
	                    },
               "_api": "sky"
              };

	  // set my schema
	  raise pds event new_data_available 
            attributes
              {"namespace": "myCloud",
               "keyvalue": "mySchemaName",
	       "value": my_schema,
	       "_api": "sky"
              };

          // set my cloudType
	  raise pds event new_settings_attribute 
            attributes
	      {"setRID"   : "a169x695",
  	       "setAttr"  : "myCloudType",
	       "setValue" : "cloudTypeThing",
	       "_api": "sky"
              };
	     
          // initialize my profile
	  raise pds event new_profile_item_available 
            attributes
	      {"myProfileName"  : name,
	       "myProfilePhoto" : photo,
	       "vin": vin,
	       "deviceId": device_id,
	       "_api": "sky"
	      };

	   // // create the carvoyant vehicle
	   // raise carvoyant event update_account
           //    attributes
           //      {"deviceId" : device_id,
	   //       "label" : name,
	   // 	"vin" : vin,
	   // 	"mileage": mileage,
	   //       "_api": "sky"
           //      } if vin && device_id  // need to ensure carvoyant has been set up? 

	  log(">>>>>>>> device_id >>>>>>> " + device_id);

          // send the device ID 
	  raise carvoyant event new_device_id
            attributes
              {"deviceId" : device_id,
	       "_api": "sky"
              } if device_id;

	  log(">>>>>>>> device_id >>>>>>> " + device_id);

	  raise fuse event new_vehicle_added 
            attributes
	      {"vehicle_name": name,
	       "_api": "sky"
	      };
        }
    }

    // meant to generally route events to owner. Extend eventex to choose what gets routed
    rule route_to_owner {
      select when fuse new_vehicle_added
               or fuse vehicle_initialzed
      pre {
        owner = fleetChannel();
      }
      {
        send_directive("Routing to owner")
          with channel = owner 
           and attrs = event:attrs();
        event:send({"cid": owner}, "fuse", event:type())
          with attrs = event:attrs();
      }
    }

    rule auto_approve_pending_subscriptions {
        select when cloudos subscriptionRequestPending
           namespace re/fuse-meta/gi

        {
            noop();
        }

        fired {
            raise cloudos event subscriptionRequestApproved
                with eventChannel = event:attr("eventChannel")
                and  _api = "sky";
        }
    }


    // ---------- set up and configure me ----------

    // not sure we need the full "settings framework"
    rule load_app_config_settings is inactive {
      select when web sessionLoaded 
               or fuse initialize_config
      pre {
        schema = [
          {"name"     : "deviceId",
           "label"    : "Device ID",
           "dtype"    : "text"
          },
          {"name"     : "apiKey",
           "label"    : "Carvoyant API Key",
           "dtype"    : "text"
          },
          {"name"     : "secToken",
           "label"    : "Carvoyant security token (keep private)",
           "dtype"    : "text"
          }
	  
        ];
        data = {
	  "deviceId" : "C201300398",
	  "apiKey": keys:carvoyant_test("apiKey"),
	  "secToken": keys:carvoyant_test("secToken")
        };
      }
      always {
        raise pds event new_settings_schema
          with setName   = "Carvoyant"
          and  setRID    = carvoyant:namespace()
          and  setSchema = schema
          and  setData   = data
          and  _api = "sky";
      }
    }

    rule request_config_for_vehicle {
      select when fuse new_vehicle_configuration
      pre {
        // figure out who my fleet is
	fleet_chan = fleetChannel();
      }
      {
        send_directive("Advertising an outdated config for vehicle")
          with new_config = event:attrs();
	send:event({"cid": fleet_chan}, "fuse", "config_outdated");
      }	  
      always {
        log ">>> looking for new configuration >>>>";
      }
    }

    rule initialize_vehicle {
      select when fuse vehicle_uninitialized
      pre {
        config = pds:get_item(carvoyant:namespace(), "config");
      }
      if (not config{"deviceId"}.isnull() ) then {
        send_directive("initializing vehicle " + config{"deviceId"});
      }
      fired {
        raise fuse event need_initial_carvoyant_subscriptions;

	raise fuse event need_vehicle_data;

	raise fuse event need_vehicle_status;

	raise fuse event vehicle_initialized;
      } else {
        log ">>>>>>>>>>>>>>>>>>>>>>>>> vehicle not configure <<<<<<<<<<<<<<<<<<<<<<<<<";
        raise fuse event vehicle_not_configured ;
      }
    }

    rule iniialize_subscriptions {
      select when fuse need_initial_carvoyant_subscriptions
      foreach [{"subscription_type": "ignitionStatus",
                "minimumTime": 0},
	       {"subscription_type": "lowBattery",
	        "minimumTime": 60},
	       {"subscription_type": "troubleCode",
	        "notification_period": "INITIALSTATE",
	        "minimumTime": 60},
	       {"subscription_type": "numericDataKey",
	        "minimumTime": 60,
		"dataKey": "GEN_FUELLEVEL",
		"thresholdValue": 20,
		"relationship": "BELOW"}
	      ] setting (subscription)
     	// send_directive("Adding initial subscription") with subscription = subscription;
        fired {	
          raise carvoyant event new_subscription_needed 
	    attributes
	      subscription
	        .put(["idempotent"], true);
        }
    }

    // ---------- vehicle data rules ----------
    rule update_vehicle_data {
      select when fuse need_vehicle_data
      pre {

        vid = carvoyant:vehicle_id();
	incoming = event:attrs() || {};
         // raw_vehicle_info = incoming{"vin"}.isnull() => carvoyant:get_vehicle_data(carvoyant:carvoyant_vehicle_data(vid))
         //                                              | incoming;

        raw_vehicle_info = incoming{"vin"}.isnull() => carvoyant:carvoyantVehicleData(vid)
                                                     | incoming;

	profile = pds:get_all_me();

	status = vehicleStatus() || {};

	dtc = {"code": status{["GEN_DTC","value"]},
	       "id":  status{["GEN_DTC","id"]},
	       "timestamp":  status{["GEN_DTC","timestamp"]}
	      };

	speed = raw_vehicle_info{"running"} => status{["GEN_SPEED","value"]}
	                                     | "0";


	vehicle_info = raw_vehicle_info
	                 .put(["profilePhoto"], profile{"myProfilePhoto"})
	                 .put(["profileName"], profile{"myProfileName"})
	                 .put(["vin"], profile{"vin"})
	                 .put(["deviceId"], profile{"deviceId"})
			 .put(["DTC"], dtc)
			 .put(["fuellevel"], status{["GEN_FUELLEVEL","value"]})
			 .put(["address"], status{["GEN_NEAREST_ADDRESS","value"]})
			 .put(["speed"], speed)
			 .put(["heading"], status{["GEN_HEADING","value"]})

      }
      {send_directive("Updated vehicle data for #{vid}") with
         id = vid and
         values = vehicle_info and
	 namespace = carvoyant:namespace();
       event:send({"cid": fleetChannel()}, "fuse", "updated_vehicle") with
         attrs = {"keyvalue": "vehicle_info",
	          "vehicleId": vid,
	          "value": vehicle_info.encode()
		 };
      }

      always {
        raise fuse event updated_vehicle_data attributes vehicle_info;

        raise pds event new_data_available
	  attributes {
	    "namespace": carvoyant:namespace(),
	    "keyvalue": "vehicle_info",
	    "value": vehicle_info
	              .delete(["_generatedby"])
	              .delete(["deviceId"]),
            "_api": "sky"
 		   
	  };
	raise fuse event updated_mileage
	  with new_mileage = vehicle_info{"mileage"}
	   and timestamp = vehicle_info{"lastRunningTimestamp"};
      }

    }


    rule update_vehicle_status {
      select when fuse need_vehicle_status
      pre {
        vid = carvoyant:vehicle_id();
        vehicle_status = carvoyant:vehicleStatus() || {}; 
      }
      {send_directive("Updated vehicle status") with
         id = vid and
         values = vehicle_status and
	 namespace = carvoyant:namespace();
       event:send({"cid": fleetChannel()}, "fuse", "updated_vehicle") with
         attrs = {"keyvalue": "vehicle_status",
	          "vehicleId": vid,
	          "value": vehicle_status.encode()
		 };
      }

      always {
        raise fuse event updated_vehicle_status attributes vehicle_status;
        raise pds event new_data_available 
            attributes
              {"namespace": carvoyant:namespace(),
               "keyvalue": "vehicle_status",
	       "value": vehicle_status
	              	 .delete(["_generatedby"])
	              	 .delete(["deviceId"]),
	       "_api": "sky"
              };
	raise fuse event updated_mileage
	  with mileage = vehicle_status{["GEN_ODOMETER","value"]}
	   and timestamp = vehicle_status{["GEN_ODOMETER","timestamp"]};
      }

    }


    // ---------- maintainance rules ----------
    // doesn't do anything since the system forces event:send() to async mode
    rule catch_complete {
      select when system send_complete
        foreach event:attr('send_results').pick("$.result") setting (result)
        send_directive("event:send status")
	  with status = result{"status"}
	   and reason = result{"reason"}
	   and body = result{"body"}
	  ;
   }



}