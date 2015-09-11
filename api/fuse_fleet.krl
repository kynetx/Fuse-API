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
	use module b16x26 alias reports

        sharing on
        provides vehicleChannels, vehicleSummary, vehicleStatus, tripSummaries, tripsSummary, fuelSummaries, fuelSummary,
	seeFleetData, // delete after testing
	fleetDetails, vinAndDeviceIdCheck, errorSummary, showPicoStatus, createSharingChannel
    }

    global {

      vehicleChannels = function() {

         common:vehicleChannels();
      };

      seeFleetData = function(){
        ent:fleet
      };
      
      fleetDetails = function(start, end) {
        reports:fleetDetails(start, end, vehicleSummary());
      }

      vehicleSummary = function() {

        picos = CloudOS:picoList().defaultsTo({}); // tolerate lookup failures
        picos_by_id = picos.values().collect(function(x){x{"id"}}).map(function(k,v){v.head()});
	pico_ids = picos_by_id.keys();
 
	// get the subscription IDs (we don't want to use the Pico channels here...)
        vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle").defaultsTo([]);

        // collect returns arrays as values, and we only have one, so map head()
        vehicle_ecis_by_name = vehicle_ecis.collect(function(x){x{"channelName"}}).map(function(k,v){v.head()}).klog(">>> ecis by name  >>> ");


	summaries = (ent:fleet{["vehicle_info"]})
	             .defaultsTo({})
		     .map(function(k,v){v.put(["picoId"], k)
                                         .put(["channel"], vehicle_ecis_by_name{[k,"eventChannel"]})
                                       });
	summary_keys = summaries.keys();



	// which picos exist that have no summary yet? 
	missing = pico_ids.difference(summary_keys).klog(">>>> missing vehicle data here >>>>");
	responses = missing.map(function(k){CloudOS:sendEvent(picos_by_id{[k,"channel"]}, "fuse", "need_vehicle_data", account_info)}); 
	
	summaries.values()

      };

      vehicleStatus = function() {
        summaries = ent:fleet{["vehicle_status"]}
		     .map(function(k,v){v.put(["picoId"], k)
                                       });
        summaries.values();
        
      };

      tripSummaries = function(year, month) {
        trip_summaries = ent:fleet{["trip_summaries", "Y" + year, "M" + month]} || {};
	summaries = trip_summaries
		     .map(function(k,v){v.put(["picoId"], k)
		                         .put(["label"], ent:fleet{["vehicle_info", k, "label"]})
                                       });
        summaries.values();
        
      };
      tripsSummary = tripSumaries;
      

      fuelSummaries = function(year, month) {

      	vehicle_summaries = ent:fleet{["vehicle_info"]} || {};
	fuel_summaries = ent:fleet{["fuel_summaries", "Y" + year, "M" + month]} || {};

	summaries = vehicle_summaries.map(function(k, v){
		                            (fuel_summaries{k} || 
                                             {})
					      .put(["picoId"], k)
		                              .put(["profileName"], vehicle_summaries{[k, "profileName"]}  || vehicle_summaries{[k, "label"]} )
		                              .put(["fuellevel"], vehicle_summaries{[k, "fuellevel"]})
		                              .put(["mileage"], vehicle_summaries{[k, "mileage"]}) 
		                              .put(["lastWaypoint"], vehicle_summaries{[k, "lastWaypoint"]})
	                                  })

	 // summaries = ent:fleet{["fuel_summaries", "Y" + year, "M" + month]}  
	 // 	     .map(function(k,v){v.put(["picoId"], k)
	 // 	                         .put(["label"], ent:fleet{["vehicle_info", k, "label"]})
	 // 	                         .put(["fuellevel"], ent:fleet{["vehicle_info", k, "fuellevel"]})
	 // 	                         .put(["mileage"], ent:fleet{["vehicle_info", k, "mileage"]}) 
	 // 	                         .put(["lastWaypoint"], ent:fleet{["vehicle_info", k, "lastWaypoint"]})
         //                               });
        summaries.values(); 
        
      };
      fuelSummary = fuelSummaries;


      errorSummary = function() {
	summaries = ent:fleet{["vehicle_errors"]}  
		     .map(function(k,v){v.put(["picoId"], k)
		                         .put(["label"], ent:fleet{["vehicle_info", k, "label"]} || vehicle_summaries{[k, "profileName"]})
                                       });
        summaries.values();
        
      };


      findVehicleByBackchannel = function (bc) {
        garbage = bc.klog(">>>> back channel <<<<<");
        vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle");
	vehicle_ecis_by_backchannel = vehicle_ecis
                                         .collect(function(x){x{"backChannel"}})
	                                 .map(function(k,v){v.head()})
                                         ;
	vehicle_ecis_by_backchannel{bc} || {}
      };

      findVehicleByName = function (name) {
        vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle");
	vehicle_ecis_by_name = vehicle_ecis
	                         .collect(function(x){x{"channelName"}})
				 .map(function(k,v){v.head()})
				 // .klog(">>>> vehicle ECIs by name")
				 ;
	vehicle_ecis_by_name{name} || {}
      };

      vehicleNameByBackChannel = function() {
	vehicle_channel_data = findVehicleByBackchannel(meta:eci());
	vehicle_channel_data{"channelName"}.klog(">>>> vehicle name >>>> ")
      }


      // ---------- config check functions ----------
      vinAndDeviceIdCheck = function(vin, deviceId) {
        cv_vehicles = carvoyant:carvoyantVehicleData().klog(">>>>> carvoyant vehicle data >>>>") || [];

	cv_vehicles_by_deviceId = cv_vehicles
  	   	  		   .collect(function(x){x{"deviceId"}})
				   .klog(">>> cv_vehicles_by_deviceId >>>>")
				   ;

        deviceId_in_cv = cv_vehicles_by_deviceId{deviceId}.length() > 0;

	cv_vehicles_by_vin = cv_vehicles
  	   	  		   .collect(function(x){x{"vin"}})
				   .klog(">>>> cv_vehicles_by_vin >>>>")
				   ;

        vin_in_cv = cv_vehicles_by_vin{vin}.length() > 0;


	vin_and_device_id_together = vin_in_cv && 
				     deviceId_in_cv && 
    				     cv_vehicles_by_vin{vin}
				       .filter(function(v){v{"deviceId"} eq deviceId})
				       .length() > 0;


	vehicles_by_deviceId = ent:fleet{["vehicle_info"]}
	                           .defaultsTo({})
	                           .map(function(k,v){v.put(["picoId"], k)})
				   .values()
  	   	  		   .collect(function(x){x{"deviceId"}})
				   .klog(">>>> vehicles_by_deviceId >>>>>>")
				   ;

        deviceId_in_Fuse = vehicles_by_deviceId{deviceId}.length() > 0;

	vehicles_by_vin = ent:fleet{["vehicle_info"]}
	                           .defaultsTo({})
	                           .map(function(k,v){v.put(["picoId"], k)})
				   .values()
  	   	  		   .collect(function(x){x{"vin"}})
				   .klog(">>>> vehicles_by_vin >>>> ")
				   ;

	vin_in_Fuse = vehicles_by_vin{vin}.length() > 0;

	{
	 "deviceIdInCarvoyant": deviceId_in_cv,
	 "deviceIdInFuse": deviceId_in_Fuse,
	 "vinInCarvoyant": vin_in_cv,
	 "vinInFuse" : vin_in_Fuse,
	 "canAddCarvoyant": vin_and_device_id_together || (vin_in_cv && not deviceId_in_cv) || (not vin_in_cv && deviceId_in_cv)
	}

      }


      showPicoStatus = function() { 

        owner_subs = CloudOS:subscriptionList(common:namespace(),"FleetOwner");

        vehicle_statuses = vehicleChannels()
  	                      .map(function(p){ common:skycloud(p{"channel"},"b16x9","showPicoStatus", {})
                                                  .put(["picoId"], p{"picoId"})
                                                  .put(["channel"], p{"channel"})
                                              })
		              .collect( function(v){v{"picoId"}} )
			      .map(function(k,v){v.head()})
                              .klog(">>>> store statuses by id >>>>>")
                              ;

	status = {"overall": vehicle_statuses.values().all(function(v) { v{["status","overall"]} }),
                  "owners": owner_subs,
	          "vehicle": vehicle_statuses
                                .map(function(k,v){v.pick("$..overall")}),
		  "carvoyant": carvoyant:isAuthorized() 
	         }

       {"vehicles": vehicle_statuses,
        "status": status,
	"tokens": carvoyant_oauth:getTokens()
       }

      }

      // used to link fleet to more than one owner
      createSharingChannel = function(channel_name) {
        chan = CloudOS:channelCreate(channel_name);
	shared_channel = chan.put(["eci"], chan{"token"})
                             .delete(["token"])       // rename
	                     .put(["_created"], time:now())
		             .put(["channelName"], channel_name)
		             .delete(["msg"])
	                     .pset(ent:shared_channels{channel_name})
		             .klog(">>>> created channel for sharing >>> ")
		             ;
	shared_channel
      }

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
	       or fuse email_for_owner
      pre {
        owner_subs = CloudOS:subscriptionList(common:namespace(),"FleetOwner");
	// find the owner who contacted us (clould be more than one)
	matching_owner = owner_subs.filter(function(sub){ sub{"backChannel"} eq meta:eci() }).klog(">>> maching owner >>> ");
	// use any owner if no match
	owner_list = matching_owner.length() > 0 => matching_owner
                                                  | owner_subs;
        owner = owner_list.head().pick("$.eventChannel");
      }
      {
        send_directive("Routing to owner")
          with channel = owner 
           and attrs = event:attrs();
        event:send({"cid": owner}, "fuse", event:type())
          with attrs = event:attrs();
      }
    }

    // ---------- subscriptions ----------
    rule auto_approve_pending_subscriptions {
        select when cloudos subscriptionRequestPending
           namespace re/fuse-meta/gi

	pre {
	  owner_relationship = "FleetOwner";
	  owner = CloudOS:subscriptionList(common:namespace(), owner_relationship).klog(">>> current owners >>>>");
	  relationship = event:attr("relationship").klog(">>> subscription relationship >>>>");
	  channel_name = event:attr("channelName").klog(">>> incoming channel name >>>");
	  backchannel = event:attr("eventChannel");

	  valid_intro =  not ent:shared_channels{channel_name}.isnull()
                      && ent:shared_channels{[channel_name, "eci"]} eq meta:eci();

	}
	
	if ( not relationship like owner_relationship 
          || owner.length() == 0
          || valid_intro
           ) then // only auto approve the first Owner relationship
        {
            noop();
        }

        fired {
	  log ">>> auto approving subscription: #{relationship}, Back Channel: #{backchannel}";
          raise cloudos event subscriptionRequestApproved
            with eventChannel = backchannel
             and  _api = "sky";
        } else {
	  log ">>> new pending subscription: #{relationship}, Back Channel: #{backchannel} >>>";
	}
    }

    // ---------- manage vehicle picos ----------
    rule create_vehicle {
        select when fuse need_new_vehicle

	pre {
	  vehicle_attrs = event:attrs();
	  vehicle_found = vinAndDeviceIdCheck(vehicle_attrs{"vin"}, vehicle_attrs{"deviceId"});

	  should_create = not(vehicle_found{"vinInFuse"} || vehicle_found{"deviceIdInFuse"})
	  
	}
	
	if(should_create) then {
	  send_directive("vehicle_creation_ok")
	}

	fired {
	  raise explicit event "vehicle_creation_ok" attributes vehicle_attrs
	} else {
	  raise fuse event "vehicle_error" attributes {
	      "error_type": "vehicle_create",
	      "set_error": true,
	      "error_msg" : "Vehicle with same VIN or Device ID already exists"
	    };
	  raise fuse event "fleet_updated" if vehicle_found{"canAddCarvoyant"};
	}

    }


    rule create_vehicle_check {
        select when explicit vehicle_creation_ok
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
             and picoPhoto = event:attr("photo") || common:vehicle_photo 
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

	vehicle_summary = ent:fleet{["vehicle_info", name]}.klog(">>>>> data for deleted vehicle >>>>") || {};
	vid = vehicle_summary{"vehicleId"} || vehicle_summary{"deviceId"} || "none";
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

        raise carvoyant event vehicle_not_needed
	  with vid = vid
           and _api = "sky"                         if ( vid neq "none" ) ;

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

    rule find_fuse_carvoyant_diffs {
      select when fuse fleet_updated
      pre {
        cv_vehicles = carvoyant:carvoyantVehicleData(); //.klog(">>>>> carvoyant vehicle data >>>>");
	my_vehicles = vehicleSummary().klog(">>>> Fuse vehicle data >>>>>");
	no_vehicle_id = my_vehicles.filter(function(v){v{"vehicleId"}.isnull()}).klog(">>>> no vid >>>>");
	by_vehicle_id = my_vehicles.filter(function(v){not v{"vehicleId"}.isnull()}).collect(function(v){v{"vehicleId"}}); //.klog(">>>> have vid >>>>"); 
	in_cv_not_fuse = 
	  cv_vehicles.filter(function(v){ by_vehicle_id{v{"vehicleId"}}.isnull() }); // .klog(">>> no matching fuse vehicle >>>> ");
      }
      {
        send_directive("sync_fleet") with
	  fuse_not_carvoyant = no_vehicle_id and
          carvoyant_not_fuse = in_cv_not_fuse
      }
      fired {
        log ">>>> syncing fleet and carvoyant>>> ";
        raise fuse event vehicles_not_in_carvoyant with
          vehicle_data = no_vehicle_id;

	 // raise fuse event vehicles_not_in_fuse with 
	 //   vehicle_data = in_cv_not_fuse

      }
    }

    rule sync_fuse_with_carvoyant {
      select when fuse vehicles_not_in_carvoyant
      foreach event:attr("vehicle_data") setting(vehicle)
        pre {
	  pid = vehicle{"picoId"}.klog(">>> Pico ID >>>>");
	  vehicle_sub = findVehicleByName(pid);
	}
	if(not vehicle_sub{"eventChannel"}.isnull()) then
	{
	  send_directive("Initializing vehicle") with
	    vehicle_sub_info = vehicle_sub;
	  event:send({"cid": vehicle_sub{"eventChannel"}}, "carvoyant", "init_vehicle");
	}
	fired {
	  log ">>>> telling #{pid} to initialize itself with Carvoyant >>>"
	} else {
	  log ">>>> No event channel found for #{pid}"
	}
    }

    // ---------- cache vehicle data ----------
    // this is a general rule for catching updates from the vehicle and storing them in ent:fleet. 
    //   possible key values include: vehicle_info, vehicle_status, [trip_summaries,#{year},#{month}]
    //   they are appended with the vehicle name so that leaving off the name gives values for fleet
    rule update_vehicle_data_in_fleet {
      select when fuse updated_vehicle
      pre {
	keyvalue = event:attr("keyvalue").split(re/,/).klog(">>>> key value should be array >>>");
        vehicle_info = event:attr("value").decode();

	vehicle_name = vehicleNameByBackChannel();

	new_key = keyvalue.append(vehicle_name).klog(" >>> storing vehicle data here >>>> ")

      }
      {send_directive("Updated vehicle data for #{new_key.encode()} in fleet") with
         values = vehicle_info and
	 keyvalue = keyvalue and
	 namespace = carvoyant_namespace and 
	 vehicle_name = vehicle_name
	 ;
      }

      always {
        set ent:fleet{new_key} vehicle_info
      }

    }

    rule clear_fleet_cache {
      select when fuse clear_fleet_cache
      pre {
        password = event:attr("password");
	passwords_match = password eq keys:fuse_admin("password");
      }
      if (passwords_match) then 
      {
       send_directive("clearing fleet cache");
      }
      fired {
        log ">>> Clearing fleet cache >>> ";
        clear ent:fleet;
      }
    }


    // ---------- maintenance ----------
  rule find_due_reminders is inactive {
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

  rule find_due_reminders_complete is inactive {
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
  
  // ---------- fleet emails ----------
  rule send_fuse_periodic_report {
    select when fuse periodic_report
    pre {

      // configurables
      period = {"format": {"days" : -7}, // one week; must be negative
                "readable" : "weekly"
               };

      tz = event:attr("timezone").klog(">>> owner told me their timezone >>>> ");
      subj = "Your "+period{"readable"}+" report from Fuse!";

      vsum = vehicleSummary();

      // don't generate report unless there are vehicles
      html = vsum.length() > 0 => reports:fleetReport(period, tz, vsum)
                                | "";


      msg = <<
You need HTML email to see this report. 
      >>; 


      email_map = { "subj" :  subj,
		    "msg" : msg,
		    "html" : html
                  };


    }
    if(vsum.length() > 0) then
    {
      send_directive("sending email to fleet owner") with
        content = email_map;
    }
    fired {
      raise fuse event email_for_owner attributes email_map;
    }
    
  }

  rule start_periodic_report {
    select when fuse periodic_report_start
    foreach vehicleSummary() setting(vsum)

    pre {

      // drop last digit to avoid "off by a second" errors
      rcn = math:floor(time:strftime(time:now({ "tz" : "UTC" }), "%s")/10);

      period = {"format": {"days" : -7}, // one week; must be negative
                "readable" : "weekly"
               };

      tz = event:attr("timezone").klog(">>> owner told me their timezone >>>> ");

      today = time:strftime(time:now(), "%Y%m%dT000000%z", {"tz": tz.defaultsTo("UTC")});
      end = time:add(today, {"days": -1});
      start = time:add(today, period{"format"});


      channel = {"cid": vsum{"channel"}}

    }
    {
      event:send(channel, "fuse", "periodic_vehicle_report")
          with attrs = {
	    "report_correlation_number": rcn,
	    "vehicle_id": vsum{"picoId"},
	    "start": start,
	    "end": end
	  };
    }

    fired {
      raise fuse event "periodic_report_started" attributes {"report_correlation_number": rcn};
      schedule fuse event " periodic_report_timer_expired" at time:add(time:now(),{"minutes" : 2}) 
        attributes {"report_correlation_number": rcn};
    }
  }

  rule catch_periodic_vehicle_reports {
    select when fuse periodic_vehicle_report_created

    pre {
      vehicle_id = event:attr("vehicle_id");
      rcn = event:attr("report_correlation_number");
      updated_vehicle_reports = (ent:vehicle_reports{rcn})
                                    .defaultsTo([])
                                    .append(event:attr("vehicle_details").decode());
      
    }
    noop();
    always {
      set ent:vehicle_reports{rcn} updated_vehicle_reports;
      raise explicit event periodic_vehicle_report_added with
        report_correlation_number = rcn
    }

  }    

  rule check_periodic_report_status {
    select when explicit periodic_vehicle_report_added
             or explicit periodic_report_timer_expired

    pre {
      rcn = event:attr("report_correlation_number");
      vehicles_in_fleet = vehicleSummary().length().klog(">>>> vehicles in fleet >>> ");
      number_of_reports_received = (ent:vehicle_reports{rcn}).length().klog(">>>> reports received >>>>");
      timer_expired = event:type() eq "periodic_report_timer_expired"; 
    }

    if ( vehicles_in_fleet <= number_of_reports_received
      || (timer_expired && not ent:vehicle_reports{rcn}.isnull())
       ) then {
      noop();
    }
    fired {
      log "process vehicle reports ";
      log "timer expired" if(timer_expired);
      raise explicit event periodic_report_ready with
        report_correlation_number = rcn;
    } else {
      log "we're still waiting for " + (vehicles_in_fleet - number_of_reports_received) + " reports";
    }
  }

  rule process_periodic_report {
    select when explicit periodic_report_ready
    pre {
      rcn = event:attr("report_correlation_number");
    }

    noop();
    always {
     clear ent:vehicle_reports{rcn};
    }

  }
    
  // ---------- housekeeping rules ----------

  rule process_vehicle_error {
    select when fuse vehicle_error
    pre {
      error_data = event:attrs().klog(">>>> error data for vehicle >>>>");
      vehicle_name = vehicleNameByBackChannel() || "unknown vehicle";
    }
    if(event:attr("set_error")) then 
    {
      send_directive("vehicle_error") with
        error = error_data and
	name = vehicle_name
    }
    fired {
      set ent:fleet{["vehicle_errors", vehicle_name, error_data{"error_type"}]} error_data
    } else { 
      clear ent:fleet{["vehicle_errors", vehicle_name, error_data{"error_type"}]} ;
      raise fuse event dirty_errors
    }
  }

  rule clean_error_list {
    select when fuse dirty_errors
    foreach  ent:fleet{["vehicle_errors"]}.klog(">>> vehicle errors >>> ") setting (id,err)
    pre {
        picos = CloudOS:picoList()|| {}; // tolerate lookup failures
        picos_by_id = picos.values().collect(function(x){x{"id"}}).map(function(k,v){v.head()});
    } 
    if( picos_by_id{id.klog(">>>> looking for id >>> ")}.isnull() ) then {
      noop();
    }
    fired {
      clear ent:fleet{["vehicle_errors", id]};
    }
  }

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
// fuse_fleet.krl
