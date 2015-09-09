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
      use module b16x19 alias common
      use module b16x11 alias carvoyant
      use module b16x18 alias trips
      use module b16x20 alias fuel
      use module b16x26 alias reports
	
      provides vin, fleetChannel, fleetChannels, vehicleSummary, vehicleSubscription, showPicoStatus,
               missingSubscriptions,
	       trips, vehicleDetails

    }

    global {

      fleetChannel = function() {
        common:fleetChannel();
      };

      fleetChannels = function() {
        common:fleetChannels();
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

       // lastTrip = function(key) {
       //   trip = pds:get_item(carvoyant:namespace(), "last_trip_info");
       // 	key => trip{key}
       //        | trip
       // }

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
	raw_result
      }

      // these are the required subscriptions for each vehicle. 
      // they are set idempotently (only one)
      old_required_subscription_list = 
              [{"subscription_type": "ignitionStatus",
                "minimumTime": 0},
	       {"subscription_type": "lowBattery",
	        "minimumTime": 60},
	       {"subscription_type": "troubleCode",
	        "notificationPeriod": "INITIALSTATE",
	        "minimumTime": 60},
	       {"subscription_type": "numericDataKey",
	        "minimumTime": 60,
		"dataKey": "GEN_FUELLEVEL",
		"thresholdValue": 20,
		"relationship": "BELOW"}
	      ];

      // these should all be idempotent or you'll get a mess
      required_subscription_list = ["ignition_status","low_battery", "trouble_code", "fuel_level", 
                                    "vehicle_moving", "device_disconnected", "device_connected"
                                   ];
	      
      subscription_map = 
        {"vehicle_moving" :
	       {"subscription_type": "numericDataKey",
	        "minimumTime": 1,			// once per minute
		"notificationPeriod": "CONTINUOUS",
	        "dataKey": "GEN_SPEED",
		"thresholdValue": 10,
		"relationship": "ABOVE",
         	"idempotent": true
	       },
	 "fuel_purchases" :
	       {"subscription_type": "numericDataKey",
	        "minimumTime": 0,
		"notificationPeriod": "INITIALSTATE",
	        "dataKey": "GEN_FUELLEVEL",
		"thresholdValue": 90,
		"relationship": "ABOVE",
         	"idempotent": false
	       },
	 "device_disconnected" :
	       {"subscription_type": "vehicleDisconnected",
	        "minimumTime": 0,
		"notificationPeriod": "INITIALSTATE",
         	"idempotent": true
	       },
	 "device_connected" :
	       {"subscription_type": "vehicleConnected",
	        "minimumTime": 0,
		"notificationPeriod": "INITIALSTATE",
         	"idempotent": true
	       },
          "ignition_status" :
	       {"subscription_type": "ignitionStatus",
                "minimumTime": 0,
         	"idempotent": true
	       },
          "low_battery": 
	       {"subscription_type": "lowBattery",
	        "minimumTime": 60,
		"notificationPeriod": "INITIALSTATE",
         	"idempotent": true
	       },
          "trouble_code":
	       {"subscription_type": "troubleCode",
	        "notificationPeriod": "INITIALSTATE",
	        "minimumTime": 60,
         	"idempotent": true
	       },
          "fuel_level":
	       {"subscription_type": "numericDataKey",
	        "minimumTime": 60,
		"notificationPeriod": "INITIALSTATE",
		"dataKey": "GEN_FUELLEVEL",
		"thresholdValue": 20,
		"relationship": "BELOW",
         	"idempotent": true
	       }
	};


      missingSubscriptions = function(my_subs) {
        carvoyant:missingSubscriptions(required_subscription_list, subscription_map, my_subs)
      };

      subscriptionsOk = function(my_subs) {
        missing = missingSubscriptions(my_subs);
	subscription_eci = carvoyant:get_eci_for_carvoyant();
	missing.length() == 0 && 
          my_subs
           .all(function(s){s{"postUrl"}.match("re/#{subscription_eci}/".as("regexp"))})
      }


      showPicoStatus = function() {
	// rulesets
	my_rulesets = CloudOS:rulesetList(meta:eci()).pick("$.rids");
	needed_rulesets = common:requiredRulesets("vehicle").append(common:requiredRulesets("core"));
	missing = needed_rulesets.difference(my_rulesets);
	// subscription
	fleet_subscription = CloudOS:subscriptionList(common:namespace(),"Fleet").head();
	// vehicle ID
	vid = carvoyant:vehicle_id();
	// subscriptions
	subscriptions = carvoyant:getSubscription(vid);
	// carvoyant channel
	subscription_eci = carvoyant:get_eci_for_carvoyant();
	// what does carvoyant think?
	cv_vehicles = carvoyant:carvoyantVehicleData(vid);
	// profile
	me = pds:get_all_me();
	// vehicleSummary
	vehicle_summary = vehicleSummary().klog(">>>> vehicle summary >>> ");

	status = {"rulesets_ok": missing.length() == 0,
	          "eventChannel_ok": not fleet_subscription{"eventChannel"}.isnull(),
	          "backChannel_ok": not fleet_subscription{"backChannel"}.isnull(),
	          "vehicleId_match": not vehicle_summary{"vehicleId"}.isnull()
                                  && vehicle_summary{"vehicleId"} eq cv_vehicles{"vehicleId"},
		  "recieving_ok": not vehicle_summary{"lastRunningTimestamp"}.isnull(),
	          "subscriptions_ok": subscriptionsOk(subscriptions),
	          "subscription_eci_ok": not subscription_eci.isnull(),
	          "deviceId_ok": me{"deviceId"}.match(re/^(FS|C20).+$/)
                 }
 

	{"rulesets": {"installed" : my_rulesets,
		      "required": needed_rulesets,
		      "missing": missing
		     },
	 "fleet_channel": fleet_subscription,
	 "profile": me
	             .delete(["myProfilePhoto"]),
	 "carvoyant": {"subscription_channel": subscription_eci,
		       "subscriptions": subscriptions,
		       "vehicle_data": cv_vehicles
		      },
         "vehicle": {"deviceId": vid,
	             "vehicleId": vehicle_summary{"vehicleId"}, 
	             "lastRunningTimestamp": vehicle_summary{"lastRunningTimestamp"},
	             "lastWaypoint": vehicle_summary{"lastWaypoint"}
		    },
	 "status": status.put(["overall"], status.values().all(function(x){x}))
	}
      }

      // ---------- experimental ----------
      trips = function(id, limit, offset) {
          trips:trips(id, limit, offset)
      }

      vehicleDetails = function(start, end) {
          vd = reports:vehicleDetails(start, end);
          vd(vehicleSummary());
      }

    }

    // ---------- initialization ----------
    rule setup_vehicle_pico {
        select when fuse new_vehicle
 
	pre {
	   orig_attrs = event:attrs();
	   name = event:attr("name");
	   photo = event:attr("photo") || common:vehicle_photo;
           my_fleet = event:attr("fleet_channel");
           mileage = event:attr("mileage");
           my_schema = event:attr("schema");
	   device_id = (event:attr("deviceId") || "").uc();
	   vin = (event:attr("vin") || "").uc();

	   // need to take stuff from event attrs and fill our schema
	   new_profile = orig_attrs
	       	            .put(["myProfileName"], name)
			    .put(["myProfilePhoto"], photo)
			    .delete(["name"])
			    .delete(["photo"])
			    .delete(["deviceId"])
			    .put(["deviceId"], device_id.uc()) // upper case deviceId
			    .delete(["fleet_channel"])
			    .delete(["schema"])
			    .put(["_api"], sky)
			    .klog(">>>> saving profile for vehicle >>>>")
			    ;

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
            attributes new_profile;

	  raise fuse event need_vehicle_data; // initialize vehicle_summary


	  log(">>>>>>>> device_id >>>>>>> " + device_id);


        }
    }

    // meant to generally route events to owner. Extend eventex to choose what gets routed
    rule route_to_owner {
      select when fuse vehicle_initialzed
               or fuse email_for_owner
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
    rule request_config_for_vehicle is inactive {
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
        profile = pds:get_all_me();
      }
      // why not check to ensure we have a Carvoyant ID? 
      if (not profile{"deviceId"}.isnull() ) then {
        send_directive("initializing vehicle " + profile{"deviceId"});
      }
      fired {
        raise fuse event subscription_check;

	raise fuse event need_vehicle_data;

	raise fuse event need_vehicle_status;

	raise fuse event vehicle_initialized;
      } else {
        log ">>>>>>>>>>>>>>>>>>>>>>>>> vehicle not configured <<<<<<<<<<<<<<<<<<<<<<<<<";
        raise fuse event vehicle_not_configured attributes profile;
      }
    }

    rule initialize_subscriptions {
      select when fuse need_initial_subscriptions
      foreach missingSubscriptions() setting (subtype)
        pre {
      	  host = event:attr("event_host");
	}
         // if (not subscription_map{subtype}.isnull()) then 
    	 //   send_directive("Adding initial subscription") with subscription = subscription;
        fired {	
	   raise fuse event new_subscription for meta:rid() with
             subtype = subtype and
             event_host = host;

           // raise carvoyant event new_subscription_needed 
	   //   attributes subscription;
        }
    }

    rule add_subscription {
      select when fuse new_subscription
      pre {
        subtype = event:attr("subtype");


        default_host = meta:rid().klog(">>>> this rid >>>>")
                                 .match(re/vehicle/) => "cs.kobj.net"
                                                     | "kibdev.kobj.net";

        host = event:attr("event_host").defaultsTo(default_host, ">>>> using default host >>>");
        subscription = subscription_map{subtype}
                         .defaultsTo({}, "No subscription defined for #{subtype}")
	        	 .put(["event_host"], host)
			 .klog(">>> adding this subscription >>>>")
			 ;
      }
      if(not subscription_map{subtype}.isnull()) then 
      {
        send_directive("Adding #{subtype} subscription") with subscription = subscription;
      }
      fired {	
          raise carvoyant event new_subscription_needed 
	    attributes subscription;
      }
    }


    rule check_subscriptions {
      select when fuse subscription_check
      pre {
        vid = carvoyant:vehicle_id(); 
        my_subs = carvoyant:getSubscription(vid);
	// also check that subscription ECI exists! 
      }
      if( not subscriptionsOk(my_subs) ) then
      {
        send_directive("subscriptions not OK") with
	  my_subscriptions = my_subs and
	  should_have = should_have
      }
      fired {
        log ">>>> vehicle #{vid} needs subscription fix";
	raise carvoyant event dirty_subscriptions;
      } else {
        log ">>>> vehicle #{vid} subscriptions OK";
      }
    
    }


    // ---------- vehicle data rules ----------
    rule update_vehicle_data {
      select when fuse need_vehicle_data
               or fuse updated_vehicle_status // since we depend on it
               or pds profile_updated // since we store pictures, etc. in profile
      foreach fleetChannels() setting(chan)
      pre {

        vid = carvoyant:vehicle_id() || "none";
	incoming = event:attrs() || {};

        raw_vehicle_info = vid eq "none"            => {}
	                 | incoming{"vin"}.isnull() => carvoyant:carvoyantVehicleData(vid)
			 | incoming ;

	profile = pds:get_all_me().klog(">>>>>> seeing profile >>>>> ") || {};

	status = incoming{"GEN_NEAREST_ADDRESS"}.isnull() => vehicleStatus() || {}
                                                           | incoming;

	dtc = {"code": status{["GEN_DTC","value"]},
	       "id":  status{["GEN_DTC","id"]},
	       "timestamp":  status{["GEN_DTC","timestamp"]}
	      };

	speed = raw_vehicle_info{"running"} => status{["GEN_SPEED","value"]}
	                                     | "0"; 

	old_summary = vehicleSummary() || {};
	vehicleId = raw_vehicle_info{"vehicleId"} || old_summary{"vehicleId"};
	lastRunning = raw_vehicle_info{"lastRunning"} || old_summary{"lastRunning"};
                                             
	// reassemble vehicle_info object; this is ugly
	vehicle_info = raw_vehicle_info
	                 .put(["profilePhoto"], profile{"myProfilePhoto"})
	                 .put(["profileName"], profile{"myProfileName"})
	                 .put(["vin"], profile{"vin"})
	                 .put(["license"], profile{"license"})
	                 .put(["deviceId"], profile{"deviceId"})
			 .put(["DTC"], dtc)
			 .put(["fuellevel"], status{["GEN_FUELLEVEL","value"]})
			 .put(["address"], status{["GEN_NEAREST_ADDRESS","value"]})
			 .put(["voltage"], status{["GEN_VOLTAGE","value"]} || "unknown")
			 .put(["coolantTemperature"], status{["GEN_ENGINE_COOLANT_TEMP","value"]} || "unknown")
			 .put(["speed"], speed)
			 .put(["heading"], status{["GEN_HEADING","value"]})
			 .put(["mileage"], raw_vehicle_info{"mileage"} || profile{"mileage"})
			 .put(["vehicleId"], raw_vehicle_info{"vehicleId"} || old_summary{"vehicleId"})
			 .put(["lastRunningTimestamp"], raw_vehicle_info{"lastRunningTimestamp"} || old_summary{"lastRunningTimestamp"})
			 .put(["lastWaypoint"], raw_vehicle_info{"lastWaypoint"} || old_summary{"lastWaypoint"})
			 .put(["label"], raw_vehicle_info{"label"} || old_summary{"label"})
			 .put(["make"], raw_vehicle_info{"make"} || old_summary{"make"})
 			 .put(["model"], raw_vehicle_info{"model"} || old_summary{"model"})
			 .put(["year"], raw_vehicle_info{"year"} || old_summary{"year"})
			 ;

	

      }
      {send_directive("Updated vehicle data for #{vid}") with
         id = vid and
         values = vehicle_info and
	 namespace = carvoyant:namespace();
       event:send({"cid": chan.klog(">>>> fleet channel >>>>> ")}, "fuse", "updated_vehicle") with
         attrs = {"keyvalue": "vehicle_info",
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
      if(vehicle_status{"status_code"}.isnull()) then
      { send_directive("Updated vehicle status") with
          id = vid and
          values = vehicle_status and
	  namespace = carvoyant:namespace();
        event:send({"cid": fleetChannel()}, "fuse", "updated_vehicle") with
          attrs = {"keyvalue": "vehicle_status",
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
      }

    }

    rule create_periodic_vehicle_report {
      select when fuse periodic_vehicle_report

      pre {
        report_attrs = 	{"vehicle_id": event:attr("vehicle_id").defaultsTo(carvoyant:vehicle_id()),
	                 "report_correlation_number": event:attr("report_correlation_number"),
			 "vehicle_details": vehicleDetails(event:attr("start"), event:attr("end"))
                        };
       	completed_event_name = "periodic_vehicle_report_created";
      }

      {
        event:send({"cid": fleetChannel()}, "fuse", completed_event_name) with attrs = report_attrs;
      }

      fired {
        log "Vehicle report generated and sent to fleet";
	raise fuse event completed_event_name attributes report_attrs
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
// fuse_vehicle.krl