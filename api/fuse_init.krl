ruleset fuse_init {
    meta {
        name "Fuse Initiialize"
        description <<
Ruleset for initializing a Fuse account and managing vehicle picos
        >>
        author "PJW from AKO's Guard Tour code"

	use module b16x10 alias fuse_keys


        use module a169x625 alias CloudOS
        use module a169x676 alias pds
         // use module a41x174 alias AWSS3
         //     with AWSKeys = keys:aws()
        use module a16x129 version "dev" alias sendgrid with
            api_user = keys:sendgrid("api_user") and 
            api_key = keys:sendgrid("api_key") and
            from = "noreply@joinfuse.com" and
	    fromname = "Fuse-NoReply"
	use module b16x19 alias common

        errors to b16x13

        sharing on
        provides apps, S3Bucket, 
                 makeImageURLForPico, uploadPicoImage, updatePicoProfile, 
                 fleetChannel, fuseOwners
    }

    global {


        /* =========================================================
           PUBLIC FUNCTIONS & INDENTIFIERS
           ========================================================= */

       


        initPicoProfile = defaction(pico_channel, profile) {
            pico = {
                "cid": pico_channel
            };

            {
                event:send(pico, "pds", "new_profile_item_available")
                    with attrs = profile;
            }
        };

        makeImageURLForPico = function(pico_channel) {
            image_seed = math:random(100000);

            "https://s3.amazonaws.com/#{common:S3Bucket()}/#{meta:rid()}/#{pico_channel}.img?q=#{image_seed}"
        };

        uploadPicoImage = defaction(pico_channel, image_url, image) {
            pico = {
                "cid": pico_channel
            };
            image_id = "#{meta:rid()}/#{pico_channel}.img";
            image_value = this2that:base642string(AWSS3:getValue(image));
            image_type = AWSS3:getType(image);
            old_details = sky:cloud(pico_channel, "b501810x6", "detail");
            details = old_details.put(["photo"], image_url);

            {
                event:send(pico, "pds", "updated_profile_item_available")
                    with attrs = {
                        "image": image_url
                    };

                event:send(pico, "pds", "new_data_available")
                    with attrs = {
                        "namespace": "data",
                        "keyvalue": "detail",
                        "value": details.encode()
                    };

                AWSS3:upload(common:S3Bucket(), image_id, image_value)
                    with object_type = image_type;
            }
        };

        updatePicoProfile = defaction(pico_channel, profile) {
            pico = {
                "cid": pico_channel
            };

            {
                event:send(pico, "pds", "updated_profile_item_available")
                    with attrs = profile;
            }
        };

        fleetChannel = function() {
            cid =  CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.eventChannel") 
	        || pds:get_item(common:namespace(),"fleet_channel");

            {"eci": cid}
        };

	fuseOwners = function(password) {
	  password.klog(">>> got >>>") eq keys:fuse_admin{"password"}.klog(">>>> want >>>> ") => app:fuse_users || {}
	                                           | {"error":"Password not accepted"}
	};
	
    }

    // ---------- manage fleet singleton ----------
    rule kickoff_new_fuse_instance {
        select when fuse need_fleet
        pre {
	  fleet_channel = pds:get_item(common:namespace(),"fleet_channel");
        }

	// protect against creating more than one fleet pico (singleton)
	if(fleet_channel.isnull()) then
        {
            send_directive("requesting new Fuse setup");
        }
        
        fired {
            raise explicit event "need_new_fleet" 
              with _api = "sky"
 	       and fleet = event:attr("fleet") || "My Fleet"
              ;
        } else {
	  log ">>>>>>>>>>> Fleet channel exists: " + fleet_channel;
	  log ">> not creating new fleet ";
	}
    }

    rule create_fleet {
        select when explicit need_new_fleet
        pre {
            fleet_name = event:attr("fleet");
            pico = common:factory({"schema": "Fleet", "role": "fleet"}, meta:eci());
            fleet_channel = pico{"authChannel"};
            fleet = {
                "cid": fleet_channel
            };
	    pico_id = "Owner-fleet-"+ random:uuid();
	    
        }
	if (pico{"authChannel"} neq "none") then
        {

	  send_directive("Fleet created") with
            cid = fleet_channel;

          // tell the fleet pico to take care of the rest of the 
          // initialization.
          event:send(fleet, "fuse", "fleet_uninitialized") with 
            attrs = {"fleet_name": fleet_name,
                     "owner_channel": meta:eci(),
             	     "schema":  "Fleet",
	             "_async": 0 	              // we want this to be complete before we try to subscribe below
		    };

        }

        fired {

	  // put this in our own namespace so we can find it to enforce idempotency
	  raise pds event new_data_available 
            with namespace = common:namespace() 
             and keyvalue = "fleet_channel" 
             and value = fleet_channel
             and _api = "sky";

	  // set defaults for Fuse app
	  raise pds event new_settings_available for a169x676
            with setRID = meta:rid() // this rid
             and reportPreference = "on";
      

	  // make it a "pico" in CloudOS eyes
	  raise cloudos event picoAttrsSet
            with picoChannel = fleet_channel // really ought to be using subscriber channel, but don't have it...
             and picoName = fleet_name
             and picoPhoto = common:fleet_photo 
	     and picoId = pico_id
             and _api = "sky";

	  // subscribe to the new fleet
          raise cloudos event "subscribe"
            with namespace = common:namespace()
             and  relationship = "Fleet-FleetOwner"
             and  channelName = pico_id
             and  targetChannel = fleet_channel
             and  _api = "sky";

          log ">>> FLEET CHANNEL <<<<";
          log "Pico created for fleet: " + pico.encode();

	  raise fuse event new_fleet_initialized;

        } else {
          log "Pico NOT CREATED for fleet";
	}
    }

    rule show_children {
      select when fuse show_children
      pre {
        myPicos = CloudOS:picoList();
        fuseSubs = CloudOS:subscriptionList(common:namespace(),"Fleet");
      }
      {
        send_directive("Dependent children") with
          children = myPicos and
	  just_fuse = fuseSubs;   

      }
      
    }

    // this is too general for this ruleset except for identifying subscriptions
    rule delete_fleet {
      select when fuse delete_fleet
      pre {
        eci = event:attr("fleet_eci");

        fuseSub = CloudOS:subscriptionList(common:namespace(),"Fleet").head() || {};


	pico = common:find_pico_by_id(fuseSub{"channelName"});


        subChannel = fuseSub{"backChannel"};
	huh = CloudOS:cloudDestroy(eci, {"cascade" : 1}); // destroy fleet children too


      }
      {
        send_directive("Deleted fleet" ) with
          child = eci and
          fuseSub = fuseSub and
          channel = subChannel;
      }
      always {

        // not a pico I'm keeping track of anymore      
        raise cloudos event picoAttrsClear 
          with picoChannel = pico{"channel"}  // created with _LOGIN, not subscriber ECI, so look it up
           and _api = "sky";

	// get rid of the fleet_channel so we can initialize again
        raise pds event remove_old_data
            with namespace = common:namespace() 
             and keyvalue = "fleet_channel" 
             and _api = "sky";

	// unsubscribe from the first subscription that matches
	raise cloudos event unsubscribe
          with backChannel = subChannel
           and _api = "sky" if not subChannel.isnull();

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


    rule send_user_creation_email {
        select when fuse new_fleet_initialized
        pre {

	  me = pds:get_all_me();
	  my_email =  me{"myProfileEmail"} || random:uuid();
          msg = <<
A new fleet was created for #{me.encode()} with ECI #{meta:eci()}
>>;
        }

        {
            sendgrid:send("Kynetx Fleet Team", "pjw@kynetx.com", "New Fuse Fleet", msg);
        }

	always {
	  set app:fuse_users{my_email} me.put(["eci"], meta:eci());
	}
    }


    rule send_email_to_owner {
        select when fuse email_for_owner
        pre {

	  me = pds:get_all_me();
	  fleet_backchannel = CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.backChannel")
                           || "";   

          subj = event:attr("subj") || "Message from Fuse";
	  msg = event:attr("msg") || "This email contains no message";
 	  html = event:attr("html") || msg;
	  recipient =  me{"myProfileEmail"}.klog(">>>> email address >>>>") ;

//	  huh = event:attrs().klog(">>>> event attrs >>>>");

        }
	if( meta:eci().klog(">>>> came thru channel >>>>") eq fleet_backchannel.klog(">>>> fleet channel >>>>")
         && not msg.isnull()
	  ) then
        {
            sendgrid:sendhtml(me{"myProfileName"}, recipient, subj, msg, html); 
        }
    }

    // ---------- scheduled items ----------
    rule schedule_report {
      select when fuse sched_report 
               or pds new_settings_available reportPreference re/.+/
      pre {
        use_domain = "explicit";
	use_type = "periodic_report";
        scheduled = event:get_list();
	evid = 0;
	evtype = 1;
        evrid = 3; 
	report_events = scheduled.filter(function(e){e[evtype] eq "#{use_domain}/#{use_type}" && e[evrid] eq meta:rid()}).klog(">>>> report schedules >>>>");
	// clean up all but first
	isDeleted = report_events.tail().map(function(e){event:delete(e[evid])}).klog(">>> deleted events >>> ");

	// for cron spec
	hour = math:random(3).klog(">>> hour (plus 3)>>> ") + 3; // between 3 and 7
	minute = math:random(59).klog(">>>> minute >>>> ");
	dow = 0; // sunday
      }
      if (report_events.length() < 1) then // idempotent 
      {
        send_directive("schedule event for report") with
	  domain = use_domain and
 	  type = use_type
      }
      fired {
        log ">>>> scheduling event for #{use_domain}/#{use_type}";
 	 // five minutes after midnight on sun
	schedule explicit event use_type repeat "#{minute} #{hour} * * #{dow}";
      } else {
        log ">>>> event #{use_domain}/#{use_type} already scheduled " + report_events.encode();
      }
       
    }

    rule catch_periodic_report {
      select when explicit periodic_report
      pre {
        settings = pds:get_setting_data(meta:rid()).klog(">>>> my settings >>>> ");
	reportPreference = settings{"reportPreference"}; // on or off
	fleet = fleetChannel();
	owner_name = pds:get_me("myProfileName");
      }
      if(reportPreference eq "on") then {
        send_directive("Sending event for report") with settings = settings;
        event:send(fleet, "fuse", "periodic_report") with 
            attrs = {"owner_name": owner_name
		    };
      }
    }

    rule show_report_history {
      select when fuse show_history
      pre {
        use_domain = "explicit";
	use_type = "periodic_report";
        scheduled = event:get_list();
	evid = 0;
	evtype = 1;
        evrid = 3; 
	report_events = scheduled.filter(function(e){e[evtype] eq "#{use_domain}/#{use_type}" && e[evrid] eq meta:rid()}).klog(">>>> report schedules >>>>").head();
	report_history = event:get_history(report_events[evid]);
      }
      send_directive("report event history") with
        report_events = report_events and
        report_history = report_history
    }

    // ---------- fleet ----------

    // sends event to fleet. Extend eventex to determine what can be sent to fleet
    rule send_to_fleet {   
      select when fuse need_new_vehicle
      pre {
        channel = fleetChannel();
	d = "fuse"; //event:domain();
	t = event:type();
      }
      {
        event:send({"cid": channel}, d, t) with
          attrs = event:attrs();
      }
    }



    // not updated for Fuse
    rule store_tag_coupling {
        select when gtour should_couple_tag
        pre {
            lid = event:attr("lid");
            tid = event:attr("tid");
        }

        {
            coupleTagWithVehicle(tid, lid);
        }

        fired {
            set ent:tagCouplings {} if not ent:tagCouplings;
            log "COUPLING TAG #{tid} WITH VEHICLE #{lid}";
            set ent:tagCouplings{tid} lid;
            log "###############[TAG COUPLINGS]####################";
            log ent:tagCouplings;
            log "###############[TAG COUPLINGS]####################";
        }
    }

    // ---------- reminders ----------
    rule process_reminders {
      select when fuse reminders_ready
      pre {
        reminderItemTemplate = function(reminder) {
	  what = reminder{"what"};
      	  due_string = (reminder{"type"} eq "mileage") => reminder{"mileage"} + " miles"
                                                        | time:strftime(reminder{"due_date"}, "%A %d %b %Y");
          msg  = <<
    #{what}
    Due: #{due_string}

>>;
          msg
        };
        remindersForVehicle = function(vreminder) {
	  label = vreminder{"label"};
	  reminders = vreminder{"reminders"};
	  msg = <<
#{label}
#{reminders.map(reminderItemTemplate)}
>>;
	  msg
	};
        reminders = event:attr("reminders"); // array of hashes
      }
      {
        send_directive("processing reminders for owner") with reminders = reminders
      }
      fired {
        raise notification event status 
	  with application = "Fuse" 
	   and subject = "Maintenance Reminders"
	   and priority = 1
	   and description = reminders.map(reminderItemTemplate).join("\n");
      }
    }

    // ---------- housekeeping ----------
    rule log_all_the_things {
        select when fuse var_dump
        pre {
            couplings = ent:tagCouplings;
            subs = CloudOS:getAllSubscriptions();
            gid = page:env("g_id");
            meta_eci = meta:eci();
            this_session = CloudOS:currentSession();
            indici = pds:get_item(common:namespace(),"fleet_channel");
            fleet = subscriptionsByChannelName(common:namespace(), "Fleet");
            dump = {
                "g_id": gid,
                "metaECI": meta_eci,
                "currentSession": this_session,
                "couplings": couplings,
                "subs": subs,
                "indici": indici,
		"fleet": fleet
            };
        }

        {
            send_directive("varDump")
                with dump = dump;
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
