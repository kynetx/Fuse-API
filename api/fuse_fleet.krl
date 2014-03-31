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
            with namespace = FuseInit:namespace() 
             and mapvalues = {"schema": my_schema,
	                      "owner_channel": my_owner,
			      "fleet_name": fleet_name
	                     };

          

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

}
