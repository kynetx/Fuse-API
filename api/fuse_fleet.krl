ruleset fuse_fleet {
    meta {
        name "Functionality for Fleet Pico"
        description <<
Application that manages the fleet
        >>
        author "PJW from AKO GTour code"



        errors to b16x13

        use module a169x625  alias CloudOS
        use module a169x676  alias pds
	use module b16x19 alias common
        use module b16x16 alias FuseInit

        sharing on
        provides vehicleChannels, seeFleetData, vehicleSummary, vehicleStatus
    }

    global {

      S3Bucket = common:S3Bucket();

      // this is complicated cause we want to return the subscription channel for the vehicle, not the _LOGIN channel
      vehicleChannels = function() {

         picos = CloudOS:picoList() || {}; // tolerate lookup failures

	 // the rest of this is to return subscription ECIs rather than _LOGIN ECIs. Ought to be easier. 
         vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle")
                     || [];   

         // collect returns arrays as values, and we only have one, so map head()
         vehicle_ecis_by_name = vehicle_ecis.collect(function(x){x{"channelName"}}).map(function(k,v){v.head()});

	 res = picos.map(function(k,p){
	   id = p{"id"};
	   p.put(["channel"],vehicle_ecis_by_name{[id,"eventChannel"]});
	 }).values();
	 res
      };

      seeFleetData = function(){
        ent:fleet
      };

      vehicleSummary = function() {
        ent:fleet{["vehicle_info"]}
      };

      vehicleStatus = function() {
        ent:fleet{["vehicle_status"]}
      };

      findVehicleByBackchannel = function (bc) {
        garbage = bc.klog(">>>> back channel <<<<<");
        vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle");
	vehicle_ecis_by_backchannel = vehicle_ecis.collect(function(x){x{"backChannel"}}).map(function(k,v){v.head()}).klog(">>> vehicle_ecis_by_backchannel <<<<<");
	vehicle_ecis_by_backchannel{bc}
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
              {"namespace": common:namespace(),
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
        owner = CloudOS:subscriptionList(common:namespace(),"FleetOwner").head().pick("$.eventChannel");
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

	pre {
	  fleet_channel = event:attr("eventChannel");
	}

        {
            noop();
        }

        fired {
            raise cloudos event subscriptionRequestApproved
                with eventChannel = fleet_channel
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
          event:send(vehicle, "fuse", "new_vehicle") with 
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

	  // subscribe to the new vehicle
          raise cloudos event "subscribe"
            with namespace = common:namespace()
             and  relationship = "Vehicle-Fleet"
             and  channelName = pico_id
             and  targetChannel = channel
             and  _api = "sky";

          log ">>> VEHICLE CHANNEL <<<<";
          log "Pico created for vehicle: " + pico.encode();

        } else {
          log ">>> VEHICLE CHANNEL <<<<";
          log "Pico NOT CREATED for vehicle " + name;
	}
    }

    rule show_vehicles {
      select when fuse show_vehicles
      pre {
        myPicos = CloudOS:picoList();
        fuseSubs = CloudOS:subscriptionList(common:namespace(),"Vehicle");
      }
      {
        send_directive("Dependent children") with
          children = myPicos and
	  just_fuse = fuseSubs;   

      }
      
    }

    // this is too general for this ruleset except for identifying subscriptions
    // FIXME: this doesn't (yet) delete the vehicle data from the fleet entity variable
    rule delete_vehicle {
      select when fuse delete_vehicle
      pre {
        eci = event:attr("vehicle_eci");

	// use the eci to look up the subscription to delete
        this_sub = CloudOS:subscriptionList(common:namespace(),"Vehicle")
	           .filter(function(sub){sub{"eventChannel"} eq eci})
		   .head() 
                || {};   // tolerate lookup failures


	this_pico = common:find_pico_by_id(this_sub{"channelName"}).klog(">>>>>>>>>>> pico <<<<<<<<<<<<<<<");

	this_pico_id = this_sub{"channelName"};

        this_sub_channel = this_sub{"backChannel"};
	huh = CloudOS:cloudDestroy(eci); 
      }
      {
        send_directive("Deleted vehicle" ) with
          child = eci and
	  id = this_pico_id and
//          allSubs = CloudOS:subscriptionList(common:namespace(),"Vehicle") and
          fuseSub = this_sub and
          channel = this_sub_channel;
      }
      always {

        // not a pico I'm keeping track of anymore      
        raise cloudos event picoAttrsClear 
          with picoChannel = this_pico{"channel"}
           and _api = "sky";

	raise cloudos event unsubscribe
          with backChannel = this_sub_channel
           and _api = "sky" if not this_sub_channel.isnull();

      }
      
    }

    rule clear_out_pico is inactive {  // dangerous...
      select when maintenance clear_out_pico
      pre {
        picos = CloudOS:picoList();
	eci = picos.keys().head(); // clear the first one
      }	   
      send_directive("Clearing pico #{eci}") ;
      always {

        // not a pico I'm keeping track of anymore      
        raise cloudos event picoAttrsClear 
          with picoChannel = eci  // created with _LOGIN, not subscriber ECI, so look it up
           and _api = "sky";
      }

    }

    rule send_vehicle_new_config {
      select when fuse config_outdated
      foreach vehicleChannels().pick("$..channel") setting (vehicle_channel)
        pre {
	  tokens = ent:account_info; 
	}
	{
	  send_directive("Sending Carvoyant config to " + vehicle_channel) with tokens = tokens;
 	  event:send({"cid": vehicle_channel}, "carvoyant", "new_tokens_available");
	}
    }


    // ---------- cache vehicle data ----------

    rule update_vehicle_data {
      select when fuse updated_vehicle
      pre {
        vid = event:attr("vehicleId");
	keyvalue = event:attr("keyvalue");
        vehicle_info = event:attr("value").decode();

	// why am I gettting this?  Oh, yeah, we need to made vehicle_id and vehicle channel so we'll do that here...
	vehicle_channel = findVehicleByBackchannel(meta:eci()).klog(">>>>>>>>>>>> vehicle channel <<<<<<<<<<<<<");


      }
      {send_directive("Updated vehicle data for #{keyvalue} in fleet") with
         id = vid and
         values = vehicle_info and
	 keyvalue = keyvalue and
	 namespace = carvoyant_namespace and 
	 vehicle_channel = vehicle_channel
	 ;
      }

      always {
        set ent:fleet{[keyvalue, vid]} vehicle_info
      }

    }

    rule clear_fleet_cache {
      select when fuse clear_fleet_cache
      always {
        clear ent:fleet
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
