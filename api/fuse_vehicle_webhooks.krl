 ruleset fuse_vehicle_webhooks {
  meta {
    name "Fuse Vehicle Webhooks App"
    description <<
Let user specify webhooks for their vehicle
    >>
    author "PJW"
    sharing on

    errors to b16x13

    // use module b16x10 alias fuse_keys

    use module b16x19 alias common
	
  }

  global {


  }

  rule store_url {
    select when fuse webhook_url
    pre {
      trigger = event:attr("trigger");
      url = event:attr("url").klog(">>>> Setting webhook for #{trigger} as >>>>>");
    }
    always {
      set ent:webooks{trigger} url;
    }
  }

  rule route_trip {
    select when fuse new_trip_saved
    pre {
      tripSummary = event:attr("tripSummary");
      url = ent:webkooks{event:type()}.klog(">>> using this URL >>>>>");
    }
    { send_directive("Routing trip ")
        with trip_summary = tripSummary;
      http:post(url) with
        headers = {"content-type": "application/json"} and
        body = tripSummary
    }
  }


}
// fuse_vehicle_webhooks.krl
