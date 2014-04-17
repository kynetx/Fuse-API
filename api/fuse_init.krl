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
            application = "Fuse"
	use module b16x19 alias common

        errors to b16x13

        sharing on
        provides fleet_photo, apps, S3Bucket, 
                 makeImageURLForPico, uploadPicoImage, updatePicoProfile, 
                 fleetChannel, 
                 dereference, factory
    }

    global {


        /* =========================================================
           PUBLIC FUNCTIONS & INDENTIFIERS
           ========================================================= */

       fleet_photo = "https://dl.dropboxusercontent.com/u/329530/fuse_fleet_pico_picture.png";

           // rulesets we need installed in every Guard Tour Pico
           apps = {
               "core": [
                   "a169x625.prod",  // CloudOS Service
                   "a169x676.prod",  // PDS
                   "a16x161.prod",   // Notification service
                   "a169x672.prod",  // MyProfile
                   "a41x174.prod",   // Amazon S3 module
                   "a16x129.dev",    // SendGrid module
//  don't think we really want this everywhere...                 "b16x16.prod",    // Fuse Fleet
		   "b16x13.prod"     // Fuse errors
               ],
               "fleet": [
                   "b16x17.prod"  // fuse_fleet.krl
               ],
               "vehicle": [
                   "b16x9.prod",  // fuse_vehicle.krl
		   "b16x11.prod", // fuse_carvoyant.krl
		   "b16x18.prod"  // fuse_trips.krl
               ],
               "unwanted": [ 
                   "a169x625.prod",
                   "a169x664.prod",
                   "a169x676.prod",
                   "a169x667.prod",
                   "a16x161.prod",
                   "a41x178.prod",
                   "a169x672.prod",
                   "a169x669.prod",
                   "a169x727.prod",
                   "a169x695.prod",
                   "b177052x7.prod"
               ]
           };


        S3Bucket = common:S3Bucket();
  
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

            "https://s3.amazonaws.com/#{S3Bucket}/#{meta:rid()}/#{pico_channel}.img?q=#{image_seed}"
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

                AWSS3:upload(S3Bucket, image_id, image_value)
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
            cid =  ent:fleet_channel
                || CloudOS:subscriptionList(common:namespace(),"Fleet").head().pick("$.eventChannel");

            {"cid": cid}
        };

	// not updated for Fuse
        coupleTagWithVehicle = defaction(tid, lid) {
            vehicle = sky:cloud(fleetChannel().pick("$.cid"), "b501810x4", "translate", {
                "id": lid
            });
            vehicle_details = sky:cloud(vehicle{"cid"}, "b501810x6", "detail");
            fresh_tags = (vehicle_details{"tags"} || []).append(tid);
            vehicle_with_tags = vehicle_details.put(["tags"], fresh_tags);

            {
                event:send(vehicle, "pds", "new_data_available")
                    with attrs = {
                        "namespace": "data",
                        "keyvalue": "detail",
                        "value": vehicle_with_tags.encode()
                    };
            }
        };

	// not updated for Fuse
        dereference = function(tag, identity) {
            couplings = ent:tagCouplings;
            lid = couplings{tag};
            scanner = sky:cloud(identity, "a169x676", "get_all_me");
            scanner_role = (scanner{"role"}.match(re/manager/i)) => "manager" | (scanner{"role"}.match(re/guard/i)) => "guard" | 0;
            // if they have a role and there is a vehicle id associated with the tag, if they don't have a role, they aren't authorized
            // to see anything for the tag anyway, and if we make it to the fallback, it means they have a role but there is no vehicle id
            // associated with the tag.
            page = (scanner_role && lid) => tagPages{scanner_role} + "?id=#{lid}" | (not scanner_role) => tagPages{"notAuthorized"} | tagPages{"notCoupled"};
            uri = "#{GTOUR_URI}#{page}";
            {"uri": uri, "couplings": couplings, "tag": tag, "lid": lid, "identity": identity}
        };

	// only ruleset installs are specific to fuse. Generalize? 
        factory = function(pico_meta, parent_eci) {
	  pico_schema = pico_meta{"schema"};
          pico_role = pico_meta{"role"};
          pico = CloudOS:cloudCreateChild(parent_eci);
          pico_auth_channel = pico{"token"};
          remove_rulesets = CloudOS:rulesetRemoveChild(apps{"unwanted"}, pico_auth_channel);
          install_rulesets = CloudOS:rulesetAddChild(apps{"core"}, pico_auth_channel);
          installed_rulesets = 
             (pico_role.match(re/fleet/gi)) => CloudOS:rulesetAddChild(apps{"fleet"}, pico_auth_channel)
                                             | CloudOS:rulesetAddChild(apps{"vehicle"}, pico_auth_channel);
          {
             "schema": pico_schema,
             "role": pico_role,
             "authChannel": pico_auth_channel,
	     "installed_rulesets": installed_rulesets
          }
        };
    }

    // ---------- manage fleet singleton ----------
    rule kickoff_new_fuse_instance {
        select when fuse initialize
        pre {
	  fleet_channel = pds:get_item(namespace(),"fleet_channel");
        }

	// protect against creating more than one fleet pico (singleton)
	if(fleet_channel.isnull()) then
        {
            send_directive("requsting new Fuse setup");
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
            pico = factory({"schema": "Fleet", "role": "fleet"}, meta:eci());
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
            with namespace = namespace() 
             and keyvalue = "fleet_channel" 
             and value = fleet_channel
             and _api = "sky";

	  // make it a "pico" in CloudOS eyes
	  raise cloudos event picoAttrsSet
            with picoChannel = fleet_channel
             and picoName = fleet_name
             and picoPhoto = fleet_photo 
	     and picoId = pico_id
             and _api = "sky";

	  // subscribe to the new fleet
          raise cloudos event "subscribe"
            with namespace = namespace()
             and  relationship = "Fleet-FleetOwner"
             and  channelName = pico_id
             and  targetChannel = fleet_channel
             and  _api = "sky";

          log ">>> FLEET CHANNEL <<<<";
          log "Pico created for fleet: " + pico.encode();

        } else {
          log "Pico NOT CREATED for fleet";
	}
    }

    rule show_children {
      select when fuse show_children
      pre {
        myPicos = CloudOS:picoList();
        fuseSubs = CloudOS:subscriptionList(namespace(),"Fleet");
      }
      {
        send_directive("Dependent children") with
          children = myPicos and
	  just_fuse = fuseSubs;   

      }
      
    }

    // this is too general for this ruleset except for identifying subscriptions
    rule delete_child {
      select when fuse delete_fleet
      pre {
        eci = event:attr("fleet_eci");
        fuseSub = CloudOS:subscriptionList(namespace(),"Fleet").head() || {};
        subChannel = fuseSub{"backChannel"};
	huh = CloudOS:cloudDestroy(eci, {"cascade" : 1}); // destroy fleet children too
      }
      {
        send_directive("Deleted child" ) with
          child = eci and
          fuseSub = fuseSub and
          channel = subChannel;
      }
      always {

        // not a pico I'm keeping track of anymore      
        raise cloudos event picoAttrsClear 
          with picoChannel = eci 
           and _api = "sky";

	// get rid of the fleet_channel so we can initialize again
        raise pds event remove_old_data
            with namespace = namespace() 
             and keyvalue = "fleet_channel" 
             and _api = "sky";

	// unsubscribe from the first subscription that matches
	raise cloudos event unsubscribe
          with backChannel = subChannel
           and _api = "sky" if not subChannel.isnull();

      }
      
    }



    rule cache_index_channel is inactive {
        select when fuse new_fleet
        noop();
        fired {
            set ent:fleet_channel event:attr("fleet_channel");
        }
    }

    rule send_user_creation_email {
        select when fuse new_fleet
        pre {

	  me = pds:get_all_me();
          msg = <<
                A new fleet was created for me.encode();

            >>;
        }

        {
            sendgrid:send("Kynetx Fleet Team", "pjw@kynetx.com", "New Fuse Fleet", msg);
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

    // ---------- maintenance ----------
    rule log_all_the_things {
        select when fuse var_dump
        pre {
            couplings = ent:tagCouplings;
            subs = CloudOS:getAllSubscriptions();
            gid = page:env("g_id");
            meta_eci = meta:eci();
            this_session = CloudOS:currentSession();
            indici = ent:fleet_channel;
            fleet = subscriptionsByChannelName(namespace(), "Fleet");
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
