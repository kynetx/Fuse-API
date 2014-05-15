ruleset fuse_bootstrap {
    meta {
        name "Fuse Bootstrap"
        description <<
            Bootstrap ruleset for Fuse
        >>

        use module a169x625 alias CloudOS
        use module a169x676 alias pds

    }

    global {

        apps = {
            "core": [
                   "a169x625.prod",  // CloudOS Service
                   "a169x676.prod",  // PDS
                   "a16x161.prod",   // Notification service
                   "a169x672.prod",  // MyProfile
                   "a41x174.prod",   // Amazon S3 module
                   "a16x129.dev",    // SendGrid module
		   "b16x16.prod",    // Fuse Init (owner)
		   "b16x13.prod",    // Fuse errors
		   "b16x19.prod"     // Fuse common
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
    }

    rule strap_some_boots {
        select when fuse bootstrap
        pre {
	  remove_rulesets = CloudOS:rulesetRemoveChild(apps{"unwanted"}, pico_auth_channel);
          installed = CloudOS:rulesetAddChild(apps{"core"}, meta:eci());
          profile = {
            "username": event:attr("username") || CloudOS:username(),
            "email": event:attr("email") || ""
          };
        }

        if (installed) then {
            send_directive("New Fuse user bootstrapped");
        }

        fired {
            raise pds event "new_profile_item_available"
                attributes ({"_api": "sky"}).put(profile);
            log "Fuse user bootstrap succeeded";
        } else {
            log "Fuse user bootstrap failed";
        }
    }
}