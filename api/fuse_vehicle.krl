ruleset fuse_vehicle {
    meta {
      name "Fuse API for Vehicle"
      description <<
Fuse ruleset for a vehicle pico
    >>
      author "PJW"
      logging off


      use module b16x10 alias fuse_keys

      use module a169x625 alias CloudOS
      use module a169x676 alias pds
      use module b16x16 alias FuseInit
      use module b16x11 alias carvoyant

      errors to b16x13
	
      provides vin

    }

    global {

      S3Bucket = FuseInit:S3Bucket;
      
      carvoyant_namespace = carvoyant:namespace();

      vin = function() {
        this_vin = pds:get_me("vin");

        (this_vin.isnull()) => "NO_VIN" | this_vin
      };

      vehicle_id = function() {
        config = pds:get_item(carvoyant_namespace, "config");

         config{"deviceID"} // old name remove once we are creating vehicles with new name
        ||
         config{"deviceId"}
        ||
         pds:get_item(carvoyant_namespace, "vehicle_info").pick("$.vehicleId")
      };

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
                        "value": vehicle_details.delete(["eci"]).encode(),
                        "shouldRaiseGTourDoneEvent": "YES"
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
                        "value": fresh_details.encode(),
                        "shouldRaiseGTourDoneEvent": "YES"
                    };


                event:send(fleetChannel(), "gtour", "did_amend_pico")
                    with attrs = {
                        "details": fresh_details.encode()
                    };
            }
        };
    }

    // ---------- initialization ----------
    rule initialize_vehicle_pico {
        select when fuse vehicle_uninitialized

	pre {
	   name = event:attr("name");
	   photo = event:attr("photo");
           my_fleet = event:attr("fleet_channel");
           my_schema = event:attr("schema");

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
              {"namespace": FuseInit:namespace(),
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
	       "deviceID" : "C201300398",
	       "_api": "sky"
              };

	  raise fuse event new_vehicle 
            attributes
	      {"vehicle_name": name,
	       "_api": "sky"
	      };
        }
    }

    // meant to generally route events to owner. Extend eventex to choose what gets routed
    rule route_to_owner {
      select when fuse new_vehicle
      pre {
        owner = CloudOS:subscriptionList(namespace(),"Fleet").head().pick("$.eventChannel");
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


    // ---------- configure me ----------

    // not sure we need the full "settings framework"
    rule load_app_config_settings is inactive {
      select when web sessionLoaded 
               or fuse initialize_config
      pre {
        schema = [
          {"name"     : "deviceID",
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
        raise pds event updated_data_available
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

    // ---------- functional rules ----------

    rule show_vehicle_data {
      select when fuse need_vehicle_data
      pre {

        vid = vehicle_id();
        vehicle_info = cavoyant:get_vehicle_data(vid);

      }
      {send_directive("Vehicle Data for #{vid}") with
         id = vehicle_id and
         values = vehicle_info and
	 namespace = carvoyant_namespace;
      }

    }

   

}