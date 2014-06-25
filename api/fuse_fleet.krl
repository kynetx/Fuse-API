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
	use module b16x11 alias carvoyant
	use module b16x23 alias carvoyant_oauth

        sharing on
        provides vehicleChannels, seeFleetData, vehicleSummary, vehicleStatus
    }

    global {

      // this is complicated cause we want to return the subscription channel for the vehicle, not the _LOGIN channel
      vehicleChannels = function() {

         common:vehicleChannels();
      };

      seeFleetData = function(){
        ent:fleet
      };

      vehicleSummary = function() {

        picos = CloudOS:picoList()|| {}; // tolerate lookup failures
        picos_by_id = picos.values().collect(function(x){x{"id"}}).map(function(k,v){v.head()});
	pico_ids = picos_by_id.keys();
	summaries = ent:fleet{["vehicle_info"]};
	summary_keys = summaries.keys();

	// which picos exist that have no summary yet? 
	missing = pico_ids.difference(summary_keys).klog(">>>> missing vehicle data here >>>>");
	responses = missing.map(function(k){CloudOS:sendEvent(picos_by_id{[k,"channel"]}, "fuse", "need_vehicle_data", account_info)}); 
	
	summaries

      };

      vehicleStatus = function() {
        ent:fleet{["vehicle_status"]}
      };

      findVehicleByBackchannel = function (bc) {
        garbage = bc.klog(">>>> back channel <<<<<");
        vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle");
	vehicle_ecis_by_backchannel = vehicle_ecis.collect(function(x){x{"backChannel"}}).map(function(k,v){v.head()});
	vehicle_ecis_by_backchannel{bc} || {}
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
	       "myProfilePhoto" : common:fleet_photo,
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
               or fuse reminders_ready
      pre {
        owner = CloudOS:subscriptionList(common:namespace(),"FleetOwner").head().pick("$.eventChannel");
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
          pico = common:factory({"schema": "Vehicle", "role": "vehicle"}, meta:eci());
          channel = pico{"authChannel"};
          vehicle = {
            "cid": channel
          };
	  pico_id = "Fleet-vehicle"+ random:uuid();
        }
	if (pico{"authChannel"} neq "none") then
        {

	  // depend on this directive name and id
	  send_directive("vehicle_created") with
            cid = channel and
	    id = pico_id;

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
        name = event:attr("vehicle_name").klog(">>>>> deleting vehicle >>>> ");

	// use the eci to look up the subscription to delete
        this_sub = CloudOS:subscriptionList(common:namespace(),"Vehicle")
	           .filter(function(sub){sub{"channelName"} eq name})
		   .head()
		   .klog(">>>>>>> this_sub >>>>>>")
                || {};   // tolerate lookup failures

	// not sure why we want the sub???


	this_pico = common:find_pico_by_id(name).klog(">>>>>>>>>>> pico <<<<<<<<<<<<<<<") || {};

	something_to_do = not this_pico{"channel"}.isnull();

	this_pico_id = this_sub{"channelName"};

        this_sub_channel = this_sub{"backChannel"};
	sub_eci = this_sub{"eventChannel"}.klog(">>>>>> eci to destroy >>>>>");
	pico_eci = this_pico{"channel"}.klog(">>>>>> eci to destroy >>>>>");
	huh = (something_to_do) => CloudOS:cloudDestroy(sub_eci).klog(">>>> report from cloudDestroy >>> ") ||
	                               CloudOS:cloudDestroy(pico_eci).klog(">>>> report from cloudDestroy >>> ") 
                                 | 0;
      }
      if (something_to_do) then
      {
        send_directive("Deleted vehicle" ) with
          child = eci and
	  id = this_pico_id and
//          allSubs = CloudOS:subscriptionList(common:namespace(),"Vehicle") and
          fuseSub = this_sub and
          channel = this_sub_channel;
      }
      fired {

        // not a pico I'm keeping track of anymore      
        raise cloudos event picoAttrsClear 
          with picoChannel = this_pico{"channel"}
           and _api = "sky";

	raise cloudos event unsubscribe
          with backChannel = this_sub_channel
           and _api = "sky" if not this_sub_channel.isnull();

	clear ent:fleet{["vehicle_info", name]};

      } else {
        log ">>>>>> no vehicle to delete with name " + name;
	clear ent:fleet{["vehicle_info", name]};
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

    rule sync_fleet_with_carvoyant {
      select when fuse fleet_updated
      pre {
        cv_vehicles = carvoyant:carvoyantVehicleData().klog(">>>>> carvoyant vehicle data >>>>");
	my_vehicles = vehicleSummary(); //.klog(">>>> Fuse vehicle data >>>>>");
	no_vehicle_id = my_vehicles.values().filter(function(v){v{"vehicleId"}.isnull()}).klog(">>>> no vid >>>>");
	by_vehicle_id = my_vehicles.values().filter(function(v){not v{"vehicleId"}.isnull()}).collect(function(v){v{"vehicleId"}}); //.klog(">>>> have vid >>>>"); 
	cv_vehicles_with_no_matching_fuse_vehicle = 
	  cv_vehicles.filter(function(v){ by_vehicle_id{v{"vehicleId"}}.isnull() }).klog(">>> no matching fuse vehicle >>>> ");
      }
      {
        send_directive("sync_fleet") 
      }

    }


    // ---------- cache vehicle data ----------

    rule update_vehicle_data_in_fleet {
      select when fuse updated_vehicle
      pre {
        vid = event:attr("vehicleId");
	keyvalue = event:attr("keyvalue");
        vehicle_info = event:attr("value").decode().klog(">>>> vehicle info >>>>>");

	// why am I gettting this?  Oh, yeah, we need to match vehicle_id and vehicle channel so we'll do that here...
	vehicle_channel_data = findVehicleByBackchannel(meta:eci());
	vehicle_name = vehicle_channel_data{"channelName"};


      }
      {send_directive("Updated vehicle data for #{keyvalue} in fleet") with
         id = vid and
         values = vehicle_info and
	 keyvalue = keyvalue and
	 namespace = carvoyant_namespace and 
	 vehicle_name = vehicle_name
	 ;
      }

      always {
        set ent:fleet{[keyvalue, vehicle_name]} vehicle_info.put(["deviceId"], vid)
      }

    }

    rule clear_fleet_cache {
      select when fuse clear_fleet_cache
      always {
        clear ent:fleet
      }
    }


    // ---------- maintenance ----------
  rule find_due_reminders {
    // fire whenever we get new mileage
    select when fuse updated_vehicle_info

    pre {
      current_time = time:now();
      current_mileage = event:attr("mileage").klog(">>>> seeing this mileage >>>>> ");

      today = time:strftime(time:now(), "%Y%m%dT000000%z");

      days_since = daysBetween(time:now(), ent:last_reminder);
      

    }
    // once per day at most
    if( days_since > 1
      ) then {
      send_directive("Retrieving new reminders for today") with
	today = today and
	previous_day = ent:last_reminder;

      }

    fired {
      set ent:last_reminder today;
      raise fuse event reminders_finish;
    } else {
      log "Not enough days since last reminder: " + days_since;
    }

  }

  rule find_due_reminders_complete {
    select when fuse reminders_finish

    pre {
      all_subs = CloudOS:subscriptionList(common:namespace(),"Vehicle").pick("$.eventChannel").klog(">>> all_subs >>>>");
      createReminder = function(eci) {
        vinfo = ent:fleet{["vehicle_info", eci]};
        reminders = common:skyCloud(eci, "b16x21", "activeReminders", {"mileage": vinfo{"mileage"}, "current_time": time:now() });
	{"label": vinfo{"label"},
	 "photo": vinfo{"profilePhoto"},
	 "reminders": reminders
	}	
      };
      // flatten array of array
      reminders = all_subs.map(createReminder(eci)).klog(">>>>> all reminders >>>>>>>> ");
    }
    
    {
      send_directive("Seeing reminders") with
        reminders = reminders;
    }
    fired {
      raise fuse event reminders_ready with reminders = reminders;
    }

  }
  

    
    // ---------- housekeeping rules ----------
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
