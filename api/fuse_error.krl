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
    }

    global {
      to_name = "Kynetx Fuse Team";
      to_addr = "dev@kynetx.com";
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
            gid = page:env("g_id");
            session = CloudOS:currentSession() || "none";
            ent_keys = rsm:entity_keys().encode();

            error_email = <<
                A Fuse tour error occured with the following details:
                genus: #{genus}
                species: #{species}
                level: #{level}
                rid: #{rid}
                rule: #{rule_name}
                message: #{msg}
                eci: #{eci}
                g_id: #{gid}
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
}
