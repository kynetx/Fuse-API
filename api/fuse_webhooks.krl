 ruleset fuse_webhooks {
  meta {
    name "Fuse Webhooks Rulesets"
    description <<
Let user specify webhooks for their vehicle
    >>
    author "PJW"
    sharing on

    errors to b16x13

    // use module b16x10 alias fuse_keys

    use module b16x19 alias common

    provides webhooks
	
  }

  global {

    webhooks = function(trigger) {
      trigger.isnull() => ent:webhooks
                        | ent:webhooks{trigger};
    }

  }

  // put routing rules here. Routing rules prepare data from event (possible enriching it) for the general router below. 
  rule route_trip {
    select when fuse trip_saved
    always {
      raise explicit event route_ready attributes
        {"record": event:attr("tripSummary"),
	 "eventType": "trip_saved" // event:type() doesn't work!! 
	};
    }
  }

  rule route_alert {
    select when fuse alert_saved
    always {
      raise explicit event route_ready attributes
        {"record": event:attrs(),
	 "eventType": "alert_saved" // event:type() doesn't work!! 
	};
    }
  }

  // general rules for webhooks
  rule store_webhook {
    select when fuse webhook_url
    pre {
      trigger = event:attr("trigger");
      url = event:attr("callbackUrl").klog(">>>> Setting webhook for #{trigger} as >>>>>");
    }
    always {
      set ent:webhooks{trigger} url;
    }
  }

  rule route_event_to_webhook {
    select when explicit route_ready
    pre {
      record = event:attr("record");
      event_type = event:attr("eventType");
      url = ent:webhooks{event_type}.klog(">>> calling this URL for #{event_type} >>>>>");
    }
    if(not url.isnull()) then
    { send_directive("Routing event to webhook")
        with record = record;
      http:post(url) with
        headers = {"content-type": "application/json"} and
        body = record
    }
  }


}
// fuse_webhooks.krl
