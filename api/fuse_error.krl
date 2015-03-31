ruleset fuse_error {
    meta {
        name "Fuse Error Handler"
        description <<
            handles errors that occur in Fuse; Based on gtour_error.krl from AKO
        >>
        author "PJW & AKO"

        use module b16x10 alias fuse_keys

        use module a169x625 alias CloudOS
        use module a169x676 alias pds
        use module a16x129 alias sendgrid with
            api_user = keys:sendgrid("api_user") and 
            api_key = keys:sendgrid("api_key") 

        use module b16x19 alias common


    }

    global {
      to_name = "Kynetx Fuse Team";
      to_addr = "pjw@kynetx.com";
      subject = "Fuse System Error";
    }

    rule handle_error {
        select when system error 
        pre {
            genus = event:attr("genus");
            species = event:attr("species") || "none";
            level = event:attr("level");
            rid = event:attr("error_rid");
            rule_name = event:attr("rule_name");
            msg = event:attr("msg");
            eci = meta:eci();
            session = CloudOS:currentSession() || "none";
            ent_keys = rsm:entity_keys().encode();
	    kre = meta:host();

            error_email = <<
A Fuse error occured with the following details:
  RID: #{rid}
  Rule: #{rule_name}
  Host: #{kre}

  level: #{level}
  genus: #{genus}
  species: #{species}
  message: #{msg}

  eci: #{eci}
  txn_id: #{meta:txnId()}
  PCI Session Token: #{session}
  RSM Entity Keys: #{ent_keys}
>>;
        }

        {
            sendgrid:send(to_name, to_addr, subject, error_email);
        }
	always {
	  raise test event error_handled for b16x12 
	    attributes
	        {"rid": meta:rid(),
   	         "attrs": event:attrs()
		} 
            if event:attr("_test")
	}
    }


  // move to fuse_common.krl after we bootstrap
  rule check_pico_setup {
    select when fuse pico_setup

    pre { 

      about_me = pds:get_items(common:namespace()).defaultsTo({}).klog(">>> about me >>>");
      my_role = about_me{"schema"}.defaultsTo("person").lc();

      pico_auth_channel = meta:eci();

      // rulesets
      rulesets = common:apps;

      removed_rulesets = CloudOS:rulesetRemoveChild(rulesets{"unwanted"}.defaultsTo([]), pico_auth_channel);

      installed_rulesets = CloudOS:rulesetAddChild(rulesets{"core"}.defaultsTo([])
                                                                   .append(rulesets{my_role}.defaultsTo([]))
                                                                   .klog(">> installing these rulesets >>"), 
                                                   pico_auth_channel);

     // events
     raw_setup_events = common:setup_events;
     setup_events = raw_setup_events{"core"}.defaultsTo([])
                                              .append(raw_setup_events{my_role}.defaultsTo([]));


      // picos
      picos = CloudOS:picoList()
                 .defaultsTo({})
                 .values()
		 .klog(">> this pico's picos >>>")
		 .map(function(x){ {"cid": x{"channel"}} })
		 ; 
    }

    always {
      raise fuse event pico_setup_events for meta:rid() with setup_events = setup_events;
      raise fuse event pico_setup_children for meta:rid() with children = picos;
    }

  }

  rule raise_pico_setup_events {
    select when fuse pico_setup_events
    foreach(event:attr("setup_events")) setting(setup_event)
    always {
      raise fuse event setup_event{"event_type"} attributes setup_event{"attributes"}.defaultsTo({});
    }
  }



  rule propagate_pico_setup {
    select when fuse pico_setup_children
    foreach(event:attr("children")) setting(child)
    event:send(child, "fuse", "pico_setup")
  }


}
//fuse_error.krl