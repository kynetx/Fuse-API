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
        owner = CloudOS:subscriptionList(FuseInit:namespace(),"FleetOwner").head().pick("$.eventChannel");
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
	  pico_id = "Fleet-vehicle"+ random:uuid();
        }
	if (pico{"authChannel"} neq "none") then
        {

	  send_directive("Vehicle created") with
            cid = channel;

          // tell the vehicle pico to take care of the rest of the initialization.
          event:send(vehicle, "fuse", "vehicle_uninitialized") with 
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
             and picoId = pico_id
             and _api = "sky";

	  // subscribe to the new fleet
          raise cloudos event "subscribe"
            with namespace = FuseInit:namespace()
             and  relationship = "Vehicle-Fleet"
             and  channelName = pico_id
             and  targetChannel = channel
             and  _api = "sky";

          log ">>> VEHICLE CHANNEL <<<<";
          log "Pico created for vehicle: " + pico.encode();

        } else {
          log "Pico NOT CREATED for vehicle " + name;
	}
    }

    rule show_vehicles {
      select when fuse show_vehicles
      pre {
        myPicos = CloudOS:picoList();
        fuseSubs = CloudOS:subscriptionList(FuseInit:namespace(),"Vehicle");
      }
      {
        send_directive("Dependent children") with
          children = myPicos and
	  just_fuse = fuseSubs;   

      }
      
    }

    // this is too general for this ruleset except for identifying subscriptions
    rule delete_vehicle {
      select when fuse delete_vehicle
      pre {
        eci = event:attr("vehicle_eci");
	this_pico =  CloudOS:picoList().pick("$."+eci);
	this_pico_id = this_pico{"id"};

	// use the pico ID to look up the subscription to delete
        this_sub = CloudOS:subscriptionList(FuseInit:namespace(),"Vehicle")
	           .filter(function(sub){sub{"channelName"} eq this_pico_id})
		   .head();
        this_sub_channel = this_sub{"backChannel"};
	huh = CloudOS:cloudDestroy(eci); 
      }
      {
        send_directive("Deleted child" ) with
          child = eci and
	  id = this_pico_id and
          allSubs = CloudOS:subscriptionList(FuseInit:namespace(),"Vehicle") and
          filtered = CloudOS:subscriptionList(FuseInit:namespace(),"Vehicle").filter(function(sub){sub{"channelName"} eq this_pico_id}) and
          fuseSub = this_sub and
          channel = this_sub_channel;
      }
      always {

        // not a pico I'm keeping track of anymore      
        raise cloudos event picoAttrsClear 
          with picoChannel = eci 
           and _api = "sky";

	// unsubscribe from the first subscription that matches
	raise cloudos event unsubscribe
          with backChannel = this_sub_channel
           and _api = "sky" if not this_sub_channel.isnull();

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
