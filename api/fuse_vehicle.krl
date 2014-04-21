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
	
      provides vin, fleetChannel, vehicleInfo, lastTrip

    }

    global {

      S3Bucket = common:S3Bucket();

      carvoyant_namespace = carvoyant:namespace();

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

      vehicleInfo = function(){
        pds:get_item(carvoyant_namespace, "vehicle_info");
      }

      lastTrip = function(key) {
        trip = pds:get_item(carvoyant_namespace, "last_trip_info");
	key => trip{key}
             | trip
      }

      vehicleStatus = function(key) {
        status = pds:get_item(carvoyant_namespace, "vehicle_status");
	key => status{key} 
             | status
      }

 // not using
      initVehicle = defaction(vehicle_channel, vehicle_details) {
            vehicle = {
                "cid": vehicle_channel
            };
            
            {
                event:send(vehicle, "pds", "new_data_available")
                    with attrs = {
                        "namespace": "data",
                        "keyvalue": "detail",
                        "value": vehicle_details.delete(["eci"]).encode()
                    };

                event:send(fleetChannel(), "fuse", "new_pico") // should this be the same as the event that initializes the pico? 
                    with attrs = {
                        "details": vehicle_details.encode()
                    };
            }
        };

 // not using
        updateVehicle = defaction(vehicle_channel, vehicle_details) {
            vehicle = {
                "cid": vehicle_channel
            };
            stale_details = sky:cloud(vehicle{"cid"}, "b501810x6", "detail");
            fresh_details = (not stale_details{"error"}) => stale_details.put(vehicle_details) | vehicle_details;
            
            {
                event:send(vehicle, "pds", "new_data_available")
                    with attrs = {
                        "namespace": "data",
                        "keyvalue": "detail",
                        "value": fresh_details.encode()
                    };


                event:send(fleetChannel(), "gtour", "did_amend_pico")
                    with attrs = {
                        "details": fresh_details.encode()
                    };
            }
        };
    }

    // ---------- initialization ----------
    rule setup_vehicle_pico {
        select when fuse new_vehicle

	pre {
	   name = event:attr("name");
	   photo = event:attr("photo");
           my_fleet = event:attr("fleet_channel");
           my_schema = event:attr("schema");
//	   device_id = event:attr("device_id");

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
	       "_api": "sky"
	      };

	  // temporarily store the keys here...these will eventually have to come from Carovyant OAuth
	  raise fuse event updated_vehicle_configuration
            attributes
              {"apiKey": keys:carvoyant_test("apiKey") || "no API key available",
               "secToken": keys:carvoyant_test("secToken") || "no security token available",
	       "deviceId" : device_id,
	       "_api": "sky"
              } if false; // disabled

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
          and  setRID    = carvoyant_namespace
          and  setSchema = schema
          and  setData   = data
          and  _api = "sky";
      }
    }

    rule update_config_for_vehicle {
      select when fuse updated_vehicle_configuration
      send_directive("Updating config for vehicle")
         with new_config = event:attrs();
      always {
        raise pds event new_data_available
	  attributes {
	    "namespace": carvoyant_namespace,
	    "keyvalue": "config",
	    "value": event:attrs()
	              .delete(["_api"])
		      .delete(["_generatedby"]),
            "_api": "sky"
 		   
	  };
      }
    }

    rule initialize_vehicle {
      select when fuse vehicle_uninitialized
      pre {
        config = pds:get_item(carvoyant_namespace, "config");
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

    rule show_vehicle_data  is inactive {
      select when fuse need_vehicle_data
      pre {


        cached_info = pds:get_item(carvoyant_namespace, "vehicle_info");

        vid = carvoyant:vehicle_id();
	vehicle_info = cached_info.isnull() => carvoyant:get_vehicle_data(carvoyant:carvoyant_vehicle_data(vid))
                                             | cached_info;

      }
      {send_directive("Vehicle Data for #{vid}") with
         id = vid and
	 cached = not cached_info.isnull() and
         values = vehicle_info and
	 namespace = carvoyant_namespace;
      }

      always {
        raise fuse event updated_vehicle_data attributes vehicle_info
	 if cached_info.isnull(); // only update if we didn't cache
      }

    }

  
    rule update_vehicle_data {
      select when fuse need_vehicle_data
      pre {

        vid = carvoyant:vehicle_id();
	incoming = event:attrs();
        vehicle_info = incoming{"vin"}.isnull() => carvoyant:get_vehicle_data(carvoyant:carvoyant_vehicle_data(vid))
                                                 | incoming;

      }
      {send_directive("Updated vehicle data for #{vid}") with
         id = vid and
         values = vehicle_info and
	 namespace = carvoyant_namespace;
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
	    "namespace": carvoyant_namespace,
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
	 namespace = carvoyant_namespace;
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
              {"namespace": carvoyant_namespace,
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