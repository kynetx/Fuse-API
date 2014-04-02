ruleset fuse_fleet {
    meta {
        name "Functionality for Fleet Pico"
        description <<
Application that manages the fleet
        >>
        author "PJW from AKO GTour code"

        use module a169x625  alias CloudOS
        use module a169x676  alias pds
        use module b16x16 alias FuseInit

        errors to b16x13

        sharing on
        provides inventory, translate, internalID
    }

    global {
        inventory = function(filter) {
            index = ent:inventory;
            matches = (filter.isnull()) => index.values() | index.values().filter(function(record) {
                // if the record has a "status" attribute, IE is a report, then we also need to apply our
                // given filter against it.
                this_filter = (record{"status"}) => 
                    (record{"status"} like "re/#{filter}/gi" ||
                    record{"name"} like "re/#{filter}/gi" ||
                    record{"keywords"} like "re/#{filter}/gi" ||
                    record{"division"} like "re/#{filter}/gi" ||
                    record{"id"} eq filter) | 
                    (record{"name"} like "re/#{filter}/gi" ||
                    record{"keywords"} like "re/#{filter}/gi" ||
                    record{"division"} like "re/#{filter}/gi" ||
                    record{"id"} eq filter)

                this_filter
            });

            (not index || not matches) => [] |
            (matches.length() == 1) => matches.head() |
            this2that:transform(matches, {
                "path": ["startTime"],
                "reverse": 1,
                "compare": "datetime"
            })
        };

        internalID = function() {
            index = ent:inventory;

            (not index) => math:random(10) | index.decode().values().length()
        };

        // return an ECI given an ID.
        translate = function(id) {
            debug = ent:idToECI;
            cid_map = ent:idToECI{id};

            (cid_map) => cid_map | {"error": "no index record for #{id}"}
        };
    }

    // ---------- respond to owner ----------
    rule create_id_to_eci_mapping {
        select when fuse fleet_uninitialized

        {
            noop();
        }

        fired {
            set ent:idToECI {};
            set ent:inventory {};
        }
    }

    rule initialize_fleet_pico {
        select when fuse fleet_uninitialized

	pre {
	   fleet_name = event:attr("fleet_name");
           my_owner = event:attr("owner_channel");
           my_schema = event:attr("schema");

	}

        {
            noop();
        }

        fired {
	  // store meta info
	  raise pds event new_map_available 
            attributes 
              {"namespace": FuseInit:namespace(),
               "mapvalues": {"schema": my_schema,
	                     "owner_channel": my_owner,
			     "fleet_name": fleet_name
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
	      {"myProfileName"  : fleet_name,
	       "myProfilePhoto" : FuseInit:fleet_photo,
	       "_api": "sky"
	      };

	  raise fuse event new_fleet 
            attributes
	      {"fleet_name": fleet_name,
	       "_api": "sky"
	      };
        }
    }

    // meant to generally route events to owner. Extend eventex to choose what gets routed
    rule route_to_owner {
      select when fuse new_fleet
      pre {
        owner = CloudOS:subscriptionList(namespace(),"FleetOwner").head().pick("$.eventChannel");
      }
      {
        send_directive("Routing to owner")
          with channel = owner 
           and attrs = event:attrs();
        event:send({"cid": owner}, "fuse", "new_fleet")
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


    // ---------- manage vehicle picos ----------
    rule create_vehicle {
        select when fuse need_new_vehicle
        pre {
	  name = event:attr("name") || "Vehicle-"+math:random(99999);
          pico = FuseInit:factory({"schema": "Vehicle", "role": "vehicle"}, meta:eci());
          channel = pico{"authChannel"};
          vehicle = {
            "cid": channel
          };
        }
	if (pico{"authChannel"} neq "none") then
        {

	  send_directive("Vehicle created") with
            cid = vehicle_channel;

          // tell the vehicle pico to take care of the rest of the initialization.
          event:send(fleet, "fuse", "vehicle_uninitialized") with 
            attrs = (event:attrs()).put({"fleet_channel": meta:eci(),
             	    			 "schema":  "Vehicle",
	             			 "_async": 0    // we want this to be complete before we try to subscribe below
		    			});

        }

        fired {

	  // make it a "pico" in CloudOS eyes
	  raise cloudos event picoAttrsSet
            with picoChannel = channel
             and picoName = name
             and picoPhoto = event:attr("photo")
             and _api = "sky";

	  // subscribe to the new fleet
          raise cloudos event "subscribe"
            with namespace = namespace()
             and  relationship = "Vehicle-Fleet"
             and  channelName = "Fleet-vehicle"+ random:uuid()
             and  targetChannel = channel
             and  _api = "sky";

          log ">>> VEHICLE CHANNEL <<<<";
          log "Pico created for vehicle: " + pico.encode();

        } else {
          log "Pico NOT CREATED for vehicle " + name;
	}
    }


    // ---------- maintainance rules ----------
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
