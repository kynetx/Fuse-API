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
                   "a169x695.prod",  // Settings
                   "a41x174.prod",   // Amazon S3 module
                   "a16x129.dev",    // SendGrid module
		   "b16x16.prod",    // Fuse Init (owner)
		   "b16x13.prod",    // Fuse errors
		   "b16x19.prod"     // Fuse common
            ],
	    "unwanted": [ 
                   "a169x664.prod",	// CloudUIService 
                   "a169x667.prod",	// myThings
                   "a41x178.prod",	// SquareTag
                   "a169x669.prod",	// appStore
                   "a169x727.prod",	// CloudAPI
                   "b177052x7.prod"
            ]
        };
    }

    rule strap_some_boots {
        select when fuse bootstrap
        pre {
	  remove_rulesets = CloudOS:rulesetRemoveChild(apps{"unwanted"}, meta:eci());
          installed = CloudOS:rulesetAddChild(apps{"core"}, meta:eci());
          profile = {
            "myProfileName": event:attr("name") || CloudOS:username(),
            "myProfileEmail": event:attr("email") || "",
	    "myProfilePhoto" : event:attr("photo"),
	    "myProfilePhone" : event:attr("phone")
          };
        }

        if (installed) then {
            send_directive("New Fuse user bootstrapped") with
	      profile = profile;
        }

        fired {
            raise pds event "new_profile_item_available"
                attributes profile.put(["_api"], "sky");
            log "Fuse user bootstrap succeeded";
        } else {
            log "Fuse user bootstrap failed";
        }
    }
}