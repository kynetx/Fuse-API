ruleset fuse_init {
    meta {
        name "Fuse Owner"
        description <<
Primary ruleset for Fuse owner pico
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
        provides fleetChannel, fuseOwners, showPicoStatus, showReportHistory, createSharingChannel
    }

    global {


        fleetChannel = function() {
	    // while we're here, make sure this account has a record
  	    me = pds:get_all_me();
	    my_email =  me{"myProfileEmail"} || random:uuid();

	    thisAcctRecord = acctRecordExists(my_email) => acctRecord(my_email) 
	                                                 | makeAcctRecord(me).pset(app:fuse_users{my_email});

            cid =  CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.eventChannel")
                || pds:get_item(common:namespace(),"fleet_channel");

            {"eci": cid}
        };

	fuseOwners = function(password, account_id) {
	  password eq keys:fuse_admin("password") =>  fuse_owner(account_id)
	                                           | {"error":"Password not accepted"}
	};

	fuse_owner = function(account_id) {
	  makeAcctList = function() {
 	    {"recordCount": app:fuse_users.keys().length(),
	     "accounts": app:fuse_users
	    }
	  }
	  account_id.isnull() => makeAcctList()
	                       | app:fuse_users{account_id.replace(re# #, "+")} || {}
	}

	makeAcctRecord = function(me) {
	   me
            .delete(["_generatedby"])
            .delete(["myProfilePhoto"])
	    .put(["timestamp"], common:convertToUTC(time:now()))
            .put(["eci"], meta:eci())
	    .put(["fleet_eci"], fleetChannel())
	    ;
	}

	acctRecordExists = function(key) {
	  app:fuse_users{key}.klog(">>> record found >>>>") != 0  // persistents are never null
	}

	acctRecord = function(key) {
	  app:fuse_users{key}
	}

	showReportHistory = function() {
	  use_domain = "explicit";
   	  use_type = "periodic_report";
	  scheduled = event:get_list();
	  evid = 0;
	  evtype = 1;
	  evrid = 3; 
	  report_events = scheduled.filter(function(e){e[evtype] eq "#{use_domain}/#{use_type}" && e[evrid] eq meta:rid()}).klog(">>>> report schedules >>>>");
	  first_event_report = report_events.head();
	  report_history = event:get_history(first_event_report[evid]);
	  {"report_events": report_events,
	   "report_history": report_history
	  }
	}

        showPicoStatus = function() { 
	  fleet_channel = fleetChannel();
	  fleet_eci = fleet_channel{"eci"};
	  // takes too long right now...
//	  common:skycloud(fleet_channel{"eci"},"b16x17","showPicoStatus", {}) 
	  
	  report_info = showReportHistory();
	  report_events = report_info{"report_events"};
	  first_event_report = report_events.head();
	  
	  fleet = {"channel" : fleet_channel,
                   "status_url": "https://#{meta:host()}/sky/cloud/b16x17/showPicoStatus?_eci=#{fleet_eci}"
                  };

	  settings = pds:get_setting_data(meta:rid()) || {};

          me = pds:get_all_me();

	  status = {
            "owner_profile": me,
	    "reports": report_events.length() == 1 
	            && first_event_report[1] eq "explicit/periodic_report"
		    && first_event_report[2] eq "repeat"
		    && not report_info{["report_history", "next"]}.isnull(),
            "preferences": not settings{"reportPreference"}.isnull()
                        && not settings{"debugPreference"}.isnull(),
	    "fleet": not fleet_channel.isnull()
	  };

	  {"reports" : report_info,	
           "fleet" : fleet,
	   "preferences" : settings,
           "status": status.put(["overall"], status.values().all(function(x){x}))
	  }
	  

	}

	

	// ---------- internal ----------
	mk_fleet_sub_name = function() {
	  "Owner-fleet-"+ random:uuid()
	}

	createSharingChannel = function(password) {
	  fleet_channel = fleetChannel();
	  password eq keys:fuse_admin("password") => common:skycloud(fleet_channel{"eci"},
	                                                             "b16x17",
								     "createSharingChannel", 
								     {"channel_name": mk_fleet_sub_name()})
	                                           | {"error":"Password not accepted"}
	  
	}

      send_reports = false;
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
	    pico_id = "Owner-fleet-"+ random:uuid(); //mk_fleet_sub_name();
	    
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
             and reportPreference = "on"
	     and debugPreference = "off";
      

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

    // currently inop
    rule process_fleet_introduction {
      select when fuse fleet_introduction
      pre {
        password = event:attr("password");
	fleet_channel = event:attr("fleet_channel");
        channel_id = mk_fleet_sub_name();
	passwords_match = password eq keys:fuse_admin("password");
      }
      if (passwords_match) then // require password for now
      {
        send_directive("connecting_to_existing_fleet")
	  with fleet_channel = fleet_channel
	   and channel_id = channel_id
      }
      fired {
        log ">>> linking to existing fleet >>>> " + fleet_channel;
      } else {
        log ">>> password mismatch >>>>";
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
    // FIXME: Give the name rather than the ECI to delete. 
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


    rule finalize_new_users {
        select when fuse new_fleet_initialized
                and pds profile_updated
        pre {

	  me = pds:get_all_me();
	  my_email =  me{"myProfileEmail"};
          msg = <<
A new fleet was created for #{me.encode()} with ECI #{meta:eci()}
>>;
        }
        if not my_email.isnull() then
        {
            sendgrid:send("Kynetx Fleet Team", "fuse-support@kynetx.com", "New Fuse Fleet", msg);
        }

	fired {
	  set app:fuse_users{my_email} makeAcctRecord(me)
	}
    }

    rule link_pico_setup {
      select when pds profile_updated
      always {
        raise fuse event pico_setup
      }
    }

    rule clean_up_owners {
      select when explicit owners_polluted
      foreach app:fuse_users.keys().filter(function(x){not x.match(re/.+@.+/)}) setting (k)
      if(k.match(re/.+@.+/)) then noop()
      fired {
        log "Found email key #{k}"
      } else {
        log "Found UUID key #{k}"
      }     
    }

    rule send_email_to_owner {
        select when fuse email_for_owner
        pre {

	  me = pds:get_all_me();
	  fleet_backchannel = CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.backChannel")
                           || "";   

          subj = event:attr("subj").defaultsTo("Message from Fuse");
	  msg = event:attr("msg").defaultsTo("This email contains no message");
 	  html = event:attr("html").defaultsTo(msg);
	  recipient =  me{"myProfileEmail"}.klog(">>>> email address >>>>") ;
	  attachment = event:attr("attachment");
	  filename = event:attr("filename").defaultsTo("attached_file");

	  mailtype = attachment.isnull() => "html"
	                                  | "attachment";

//	  huh = event:attrs().klog(">>>> event attrs >>>>");

        }
	if( meta:eci().klog(">>>> came thru channel >>>>") eq fleet_backchannel.klog(">>>> fleet channel >>>>")
         && not msg.isnull()
	  ) then
          choose mailtype {
            html       => sendgrid:sendhtml(me{"myProfileName"}, recipient, subj, msg, html);
	    attachment => sendgrid:sendattachment(me{"myProfileName"}, recipient, subj, msg, filename, attachment);
          }
    }

    // ---------- preferences ----------
    rule set_debug_pref {
      select when fuse new_debug_value
      pre {
        new_val = event:attr("debug_value");
      }
      always {
        // set defaults for Fuse app
        raise pds event new_settings_attribute for a169x676
           with setRID   = meta:rid() // this rid
	    and setAttr  = "debugPreference"
	    and setValue = new_val
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

    rule clear_report_schedule {
      select when fuse report_sched_bad
      pre {
        use_domain = "explicit";
	use_type = "periodic_report";
        scheduled = event:get_list();
	evid = 0;
	evtype = 1;
        evrid = 3; 
       	report_events = scheduled.filter(function(e){e[evtype] eq "#{use_domain}/#{use_type}" && e[evrid] eq meta:rid()}).klog(">>>> report schedules >>>>");
	// clean up all 
	isDeleted = report_events.map(function(e){event:delete(e[evid])}).klog(">>> deleted events >>> ");
      }
      send_directive("deleted all scheduled events") with
        deleted_events = report_events and
	status = isDeleted
    }

    rule catch_periodic_report {
      select when explicit periodic_report
      pre {
        settings = pds:get_setting_data(meta:rid()).klog(">>>> my settings >>>> ") || {};
	      reportPreference = settings{"reportPreference"} || "on"; // on or off; default on
	      fleet = fleetChannel();
	      owner_name = pds:get_me("myProfileName");

        tz = (settings{"timezonePreference"} || settings{"timezeonePreference"} || "America/Denver").klog(">>>> using timezone for report >>> ");  // remove misspelling later

      }
      if(reportPreference eq "on" && send_reports) then {
        send_directive("Sending event for report") with settings = settings;
        event:send(fleet, "fuse", "periodic_report_start") with 
            attrs = {"owner_name": owner_name,
	    	     "timezone": tz
		    };
      }
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

    rule install_check {
      select when fuse need_init_ruleset
      send_directive("init_ruleset_installed");
      always{
        raise fuse event init_ruleset_installed
      }
    }

    rule update_account_record {
      select when fuse account_record
      pre {
        acct_id = event:attr("acct_id");
	old_record = app:fuse_users{acct_id}.defaultsTo({});
	new_record = old_record
	              .put(["timestamp"], common:convertToUTC(time:now()))
                      .put(["eci"], event:attr("new_eci").defaultsTo( old_record{"eci"} ) )
                      .put(["myProfileName"], event:attr("new_name")
                                                .defaultsTo( old_record{"myProfileName"} ) )
                      .put(["myProfileEmail"], event:attr("new_email").defaultsTo( old_record{"myProfileEmail"} ) )
                      ;
        password = event:attr("password");
	passwords_match = password eq keys:fuse_admin("password");
      }
      if (passwords_match) then  {
        send_directive("updated_account_record for #{acct_id}") with
          old_record = old_record and
          new_record = new_record;
      }
      fired {
        set app:fuse_users{acct_id} new_record if not acct_id.isnull();
      } else {
      	log ">> passwords don't match or account not found "
      }
    }


    // doesn't delete account or cloud, just the record we have here
    rule delete_fuse_owner_record {
      select when fuse delete_owner_record
      pre {
        password = event:attr("password");
	account_id = event:attr("account_id");
	passwords_match = password eq keys:fuse_admin("password");
	found_account = not app:fuse_users{account_id}.isnull();
      }
      if (passwords_match && found_account) then 
      {
       send_directive("deleting record for #{account_id}");
      }     
      fired {
        log "deleting record for #{account_id}";
	clear app:fuse_users{account_id};
      } else {
	log ">>>>> error: Password not accepted" if not passwords_match;
	log ">>>>> error: No account with ID #{account_id}" if not found_account;
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
