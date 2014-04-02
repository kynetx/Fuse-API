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
        use module a169x701 alias CloudRain
        use module a16x129 version "dev" alias sendgrid with
            api_user = keys:sendgrid("api_user") and 
            api_key = keys:sendgrid("api_key") and
            application = "Fuse"

        errors to b16x13

        sharing on
        provides fleet_photo, apps, schemas, initPico, initFleet, initVehicle, 
                    initPicoProfile, updateVehicle, destroyVehicle,
                    makeImageURLForPico, uploadPicoImage, updatePicoProfile, fleetChannel,
                    subscribePicoToPico, unsubscribePicoFromPico, subscriptionsByChannelName, namespace, 
                    division, dereference, invite, invites, users, factory
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
                   "b16x16.prod",    // Fuse Fleet
		   "b16x13.prod"     // Fuse errors
               ],
               "fleet": [
                   "b16x17.prod" // Fleet Pico
               ],
               "vehicle": [
                   "b16xYY.prod" // Fuse Vehicle Pico
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

        schemas = {
            "Fleet": {
                "meta": {
                    "schema": {
                        "type": "string"
                    },
                    "namespace": {
                        "type": "string"
                    },
                    "authChannel": {
                        "type": "string"
                    }
                },
                "profile": {
                    "role": {
                        "type": "string"
                    }
                },
                "data": {
                    "index": {
                        "type": "array",
                        "element": {
                            "type": "map",
                            "data": {
                                "name": {
                                    "type": "string"
                                },
                                "keywords": {
                                    "type": "string"
                                }
                            }
                        }
                    },
                    "idToECI": {
                        "type": "entity"
                    }
                }
            },
            "Vehicle": {
                "meta": {
                    "schema": {
                        "type": "string"
                    },
                    "namespace": {
                        "type": "string"
                    },
                    "authChannel": {
                        "type": "string"
                    }
                },
                "profile": {
                    "name": {
                        "type": "string"
                    },
                    "image": {
                        "type": "string"
                    },
                    "vin": {
                        "type": "string"
                    }
                },
                "data": {
                    "detail": {
                        "type": "map",
                        "data": {
                            "tasks": {
                                "type": "array",
                                "element": {
                                    "type": "string"
                                }
                            },
                            "directions": {
                                "type": "string"
                            },
                            "instructions": {
                                "type": "string"
                            },
                            "problemInstructions": {
                                "type": "string"
                            },
                            "keywords": {
                                "type": "string"
                            },
                            "latitude": {
                                "type": "number"
                            },
                            "longitude": {
                                "type": "number"
                            },
                            "timeline": {
                                "type": "map",
                                "data": {
                                    "timestamp": {
                                        "type": "ISO8601"
                                    },
                                    "guard": {
                                        "type": "string"
                                    },
                                    "status": {
                                        "type": "string"
                                    }
                                }
                            },
                            "tag": {
                                "type": "string"
                            },
                            "url": {
                                "type": "string"
                            }
                        }
                    }
                }
            }
        };

        S3Bucket = "k-mycloud";

        initPico = defaction(pico_channel, attrs) {
            schema = attrs{"schema"};
            pico = {
                "cid": pico_channel
            };

            {
                event:send(pico, "pds", "new_map_available") 
                    with attrs = {
                        "namespace": namespace(),
                        "mapvalues": {"schema": schema,
                    		      "authChannel":  pico_channel}.encode()
                    };
            }
        };

        initFleet = defaction(pico_channel) {
            pico = {
                "cid": pico_channel
            };

            {
                event:send(pico, "fuse", "new_pico");
            }
        };

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

        destroyVehicle = defaction(lid) {
            vehicle_channel = sky:cloud(fleetChannel().pick("$.cid"), "b501810x4", "translate", {
                "id": lid
            });
            obilterated = CloudOS:cloudDestroy(vehicle_channel.pick("$.cid"));

            {
                event:send(fleetChannel(), "gtour", "did_destroy_pico")
                    with attrs = {
                        "id": lid
                    };
            }
        };


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

        subscribePicoToPico = defaction(origin_channel, target_channel, attrs) {
            origin = {
                "cid": origin_channel
            };

            {
                event:send(origin, "cloudos", "subscribe")
                    with attrs = attrs.put(["targetChannel"], target_channel);
            }
        };

        unsubscribePicoFromPico = defaction(origin_channel, target_channel) {
            origin = {
                "cid": origin_channel
            };

            {
                event:send(origin, "cloudos", "unsubscribe")
                    with attrs = {
                        "targetChannel": target_channel
                    };
            }
        };

        subscriptionsByChannelName = function(namespace, channel_name) {
            
            subs = CloudOS:getAllSubscriptions().values().filter(function(sub) {
                sub{"namespace"} eq namespace &&
                sub{"channelName"} like "re/#{channel_name}/gi"
            });

            // if there is exactly one matching subscription, just pull it out of the 
            // filter array and return it.
            (subs.length() == 1) => subs.head() | subs
        };

        fleetChannel = function() {
            cid = (ent:indexChannelCache{"vehicle"} || subscriptionsByChannelName(namespace(), "vehicle-index").pick("$.eventChannel"));

            {"cid": cid}
        };

         namespace = function() {
           meta_id = "fuse-meta";
	   meta_id    
         };

        vin = function() {
            this_vin = pds:get_me("vin");

            (this_vin.isnull()) => "NO_VIN" | this_vin
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

    rule show_children {
      select when fuse show_children
      pre {
        myPicos = CloudOS:picoList();
      }
      {
        send_directive("Dependent children") with
          children = myPicos.encode();   

      }
      
    }

    rule delete_subscription {
      select when fuse delete_subscription
      pre {
        eci = event:attr("child");
      }
      {
        send_directive("Deleting subscription" ) with
          child = eci;

      }

      always {
        raise cloudos event unsubscribe with 
          backchannel = child;
      }
    }

    rule delete_child {
      select when fuse delete_child
      pre {
        eci = event:attr("child");
	huh = CloudOS:cloudDestroy(eci)
      }
      {
        send_directive("Deleted child" ) with
          child = eci;

      }
      always {

        // need to delete subscription...
      
        raise cloudos event picoAttrsClear 
          attributes
            {"picoChannel": eci,
	     "_api": "sky"
	    };

        raise pds event remove_old_data
            with namespace = namespace() 
             and keyvalue = "fleet_channel" 
             and _api = "sky";

      }
      
    }

    rule kickoff_new_fuse_instance {
        select when fuse initialize
        pre {
	  fleet_channel = pds:get_item(namespace(),"fleet_channel");
        }

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

	// I don't think we need to do this since we're setting pico attributes
	   // raise pds event new_item_available 
           //   with namespace = namespace() 
           //    and keyvalue = "fleet_channel" 
           //    and value = fleet_channel;

	  raise cloudos event picoAttrsSet
            with picoChannel = fleet_channel
             and picoName = fleet_name
             and picoPhoto = fleet_photo 
             and _api = "sky";

          raise cloudos event "subscribe"
            with namespace = namespace()
             and  relationship = "Owner-Fleet"
             and  channelName = "Owner-fleet-"+ random:uuid()
             and  targetChannel = fleet_channel
             and  _api = "sky";

          log ">>> FLEET CHANNEL <<<<";
          log "Pico created for fleet: " + pico.encode();
        }
    }

    rule cache_index_channel {
        select when fuse new_fleet
        noop();
        fired {
            set ent:fleet_channel event:attr("fleet_channel");
        }
    }


    // this rule listens for the event that is raised when a user has been created
    // in this case, an overlord manager. In the case of an
    // overloard manager creation, it means a new guard tour system
    // has been created and we need to send the overloard manager's data back to the cloud
    // from which the guard tour instantiation event was raised.
    rule return_to_sender {
        select when gtour did_produce_user
            role re/abinitio/i
        pre {
            user_channel = event:attr("userChannel");
            user_role = event:attr("role");
            username = event:attr("username");
            password = event:attr("password");

            user = {
                "userChannel": user_channel,
                "role": user_role,
                "username": username,
                "password": password
            };

            origin = pds:get_item("temp", "origin").decode();
        }

        {
            // raise an event into the initialization originator's cloud
            // giving them the seed manager's info and telling them initialization
            // is complete.
            event:send(origin, "gtour", "did_produce_system")
                with attrs = {
                    "managerAbInitio": user.encode()
                };
        }

        fired {
            // log whats in the PDS
            log "AKO ORIGIN";
            log origin.encode();
            log "AKO ManagerAbInitio";
            log user.encode();
            raise pds event "remove_namespace"
                with namespace = "temp"
                and  _api = "sky";
        }
    }

    rule send_user_creation_email {
        select when gtour did_produce_user
        pre {
            username = event:attr("username");
            password = event:attr("password");

            msg = <<
                A new user was created with the following details:

                username: #{username}
                password: #{password}
            >>;
        }

        {
            sendgrid:send("Kynetx Guard Tour Team", "dev@kynetx.com", "New Guard Tour User", msg);
        }
    }

    rule send_gtour_creation_notification {
        select when gtour did_produce_system 
        pre {
            manager = event:attr("managerAbInitio").decode();
            manager_username = manager{"username"};
            manager_password = manager{"password"};
            manager_channel = manager{"userChannel"};

            msg = <<
                A new guard tour system was initialized. The following seed manager
                has been created:

                username: #{manager_username}
                password: #{manager_password}
                
                Authoritative Channel: #{manager_channel}
            >>;
        }

        {
            sendgrid:send("Kynetx Guard Tour Team", "dev@kynetx.com", "New Guard Tour System Created", msg);
            send_directive("didProduceGuardTourSystem") 
                with managerAbInitio = manager;
        }
    }

    rule show_creation_form {
        select when web cloudAppSelected
        pre {
            rids = apps{"core"}.append(apps{"indexPico"}).append(apps{"managerPico"});
            install_rids = CloudOS:rulesetAddChild(rids, meta:eci());
            env_select = <<
                <select id = "gtour-creation-environment">
                    <option>development</option>
                    <option>production</option>
                </select>
            >>;
            owner_input = <<
                <input id = "gtour-owner" type = "text" placeholder = "Owner name" />
            >>;
            application_input = <<
                <input id = "gtour-application" type = "text" placeholder = "Application name" />
            >>;
            eci_input = <<
                <input id = "gtour-creation-origin" type = "hidden" value = "#{meta:eci()}" />
            >>;
            go_button = <<
                <button id = "gtour-go-btn" type = "button">Go!</button>
            >>;
            check_email_alert = <<
                <h3 id = "gtour-success-alert" style = "display:none;">A new guard tour system has been created! Check your email for further details.</h3>
            >>;
            app_panel = <<
                #{env_select}
                #{owner_input}
                #{application_input}
                #{eci_input}
                #{go_button}
                #{check_email_alert}
            >>;
        }

        {
            // oh legacy squaretag craziness...
            SquareTag:inject_styling();
            CloudRain:createLoadPanel("Guard Tour System Creation", {}, app_panel);
            emit <<
                KOBJ.GTour = KOBJ.GTour || {};
                KOBJ.GTour.envToURI = {
                    "development": "kibdev.kobj.net",
                    "production": "cs.kobj.net"
                };
                $K("#gtour-go-btn").on("click", function(e) {
                    $K("#modalSpinner").modal("show");
                    e.stopPropagation();
                    e.preventDefault();
                    var environment = KOBJ.GTour.envToURI[$K("#gtour-creation-environment").val()];
                    var owner = $K("#gtour-owner").val().replace(/\s/g, "");
                    var application = $K("#gtour-application").val().replace(/\s/g, "");
                    var creation_origin = $K("#gtour-creation-origin").val();
                    var esl = "https://"+ environment +"/sky/event/"+ creation_origin +"/"+ Math.floor(Math.random() * 9999);

                    $K.ajax({
                        url: esl,
                        type: "POST",
                        data: {
                            "_domain": "gtour",
                            "_type": "initialize",
                            "owner": owner,
                            "application": application
                        },
                        success: function(kns_directive) {
                            $K("#modalSpinner").modal("hide");
                            $K("#gtour-success-alert").fadeIn();
                        }
                    });

                });
            >>;
        }
    }

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

    rule log_all_the_things {
        select when gtour var_dump
        pre {
            couplings = ent:tagCouplings;
            subs = CloudOS:getAllSubscriptions();
            gid = page:env("g_id");
            meta_eci = meta:eci();
            this_session = CloudOS:currentSession();
            indici = ent:indexChannelCache;
            lis = subscriptionsByChannelName(namespace(), "vehicle-index");
            tis = subscriptionsByChannelName(namespace(), "tour-index");
            ris = subscriptionsByChannelName(namespace(), "report-index");
            invs = invites();
            dump = {
                "g_id": gid,
                "metaECI": meta_eci,
                "currentSession": this_session,
                "couplings": couplings,
                "subs": subs,
                "indici": indici,
                "indiciSubs": {
                    "vehicle": lis,
                    "tour": tis,
                    "report": ris
                },
                "invitations": invs
            };
        }

        {
            send_directive("varDump")
                with dump = dump;
        }

        fired {
            log "########<LOG ALL THE THINGS>##########";
            log "//////////+SESSION INFO+//////////////";
            log "g_id: " + gid;
            log "Meta ECI:" + meta_eci;
            log "CloudOS Current Session:" + this_session;
            log "/////////+END SESSION INFO+///////////";
            log "########[TAG COUPLINGS]#########";
            log couplings;
            log "########[/TAG COUPLINGS]########";
            log "########[ALL SUBSCRIPTIONS]#########";
            log subs;
            log "########[/ALL SUBSCRIPTIONS]########";
            log "########[INDEX SUBSCRIPTIONS]#######";
            log dump{"indiciSubs"};
            log "########[/INDEX SUBSCRIPTIONS]######";
            log "########[CACHED INDEX CHANNELS]#########";
            log indici;
            log "########[/CACHED INDEX CHANNELS]########";
            log "##############[INVITATIONS]]############";
            log invs;
            log "##############[/INVITATIONS]############";
            log "########</LOG ALL THE THINGS>##########";
        }
    }
}
