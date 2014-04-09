ruleset fuse_carvoyant {
  meta {
    name "Fuse Carvoyant Ruleset"
    author "Phil Windley"
    description <<
Provides rules for handling Carvoyant events
>>

    use module b16x10 alias fuse_keys
      with foo = 1

    use module a169x676 alias pds

    errors to b16x13

    provides namespace, vehicle_id, get_config, carvoyant_headers, carvoyant_vehicle_data, get_vehicle_data, 
             get_subscription,no_subscription, add_subscription, del_subscription

/* 

Design decisions:

1.) Use Carvoyant names, including camel case to avoid complex mapping calculations on keys. 

RID Key:

b16x9: fuse_vehicle.krl
b16x10: fuse_keys.krl — (in the CloudOS Keys Repo)
b16x11: fuse_carvoyant.krl
b16x12: carvoyant_module_test.krl
b16x13: fuse_error.krl
b16x16: fuse_init.krl
b16x17: fuse_fleet.krl

*/
  
  }

  global {

    // config data contains
    //   deviceId - Carvoyant device ID
    //   apiKey - API Key in http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism
    //   secToken - Access Token in http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism 

    // [TODO] 
    //  vehicle ID can't be in config data. Has to match one of them, but is supplied

    namespace = function() {
      "fuse:carvoyant";
    }

    vehicle_id = function() {
      config = pds:get_item(namespace(), "config");
      config{"deviceID"} // old name remove once we are creating vehicles with new name
     ||
      config{"deviceId"}
     ||
      pds:get_item(carvoyant_namespace, "vehicle_info").pick("$.vehicleId")
    };


    // vehicle_id is optional if creating a new vehicle profile
    // key is optional, if missing, use default
    get_config = function(vehicle_id, key) {
       carvoyant_config_key = key || namespace();
       config_data = pds:get_items(carvoyant_config_key).pick("$..config") || {};

       hostname = "dash.carvoyant.com";
       url = "https://#{hostname}/api/vehicle/#{vehicle_id}";
       config_data
         .put({"hostname": hostname,
	       "base_url": url,
	       "vehicle_id": vehicle_id || config_data{"deviceID"},
	       "apiKey" : config_data{"apiKey"} || keys:carvoyant_test("apiKey"),
	       "secToken" : config_data{"secToken"} || keys:carvoyant_test("secToken")
	      })
    }

    // ---------- general carvoyant API access functions ----------
    // See http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism for details

    // params is optional
    carvoyant_headers = function(config_data, params) {
      {"credentials": {
          "username": config_data{"apiKey"},
          "password": config_data{"secToken"},
          "realm": "Carvoyant API",
          "netloc": config_data{"hostname"} + ":443"
          },
       "params" : params || {}
      }
    };

    // functions
    carvoyant_get = function(url, config_data) {
      raw_result = http:get(url, carvoyant_headers(config_data));
      (raw_result{"status_code"} eq "200") => {"content" : raw_result{"content"}.decode(),
                                               "status_code": raw_result{"status_code"}
                                              }
                                            | raw_result
    };

    // actions
    carvoyant_post = defaction(url, params, config_data) {
      configure using ar_label = false;
      auth_data =  carvoyant_headers(config_data);
      http:post(url)
        with credentials = auth_data{"credentials"} 
         and params = params
         and autoraise = ar_label;
    };

    carvoyant_put = defaction(url, params, config_data) {
      configure using ar_label = false;
      auth_data =  carvoyant_headers(config_data);
      http:put(url)
        with credentials = auth_data{"credentials"} 
         and params = params
         and autoraise = ar_label;
    };

    carvoyant_delete = defaction(url, config_data) {
      configure using ar_label = false;
      auth_data =  carvoyant_headers(config_data);
      http:delete(url) 
        with credentials = auth_data{"credentials"} 
         and autoraise = ar_label;
    };

    // ---------- vehicle data ----------
    // vehicle ID is optional if already in pico
    carvoyant_vehicle_data = function(vehicle_id) {
      vid = vehicle_id || vehicle_id();
      config_data = get_config(vid);
      carvoyant_get(config_data{"base_url"}, config_data);
    };

    get_vehicle_data = function (vehicle_data, vehicle_number, dkey) {
      vda = vehicle_data{["content","vehicle"]};
      vd = vehicle_number.isnull() => vda | vda[vehicle_number];
      dkey.isnull() => vd | vd{dkey}
    };

    // ---------- subscriptions ----------
    carvoyant_subscription_url = function(subscription_type, config_data, subscription_id) {
       base_url = config_data{"base_url"} + "/eventSubscription/" + subscription_type;
       subscription_id.isnull() => base_url 
	                         | base_url + "/" + subscription_id
    };

    valid_subscription_type = function(sub_type) {
      valid_types = {"geoFence": true,
                     "lowBattery": true,
		     "numericDataKey": true,
		     "timeOfDay": true,
		     "troubleCode": true,
		     "ignitionStatus": true
      };
      not valid_types{sub_type}.isnull()
    }

    // check that the subscription list is empty or all in it have been deleted
    no_subscription = function(subs) {
        // a subscription doesn't exist if...
        subs{"status_code"} eq "404" ||
        (subs{"status_code"} eq "200" &&
	 subs{["content","subscriptions"]}.all(function(s){ not s{"deletionTimestamp"}.isnull() })
	)
    }


    // subscription functions
    // subscription_type is optional, if left off, retrieves all subscriptions for vehicle
    // subscription_id is optional, if left off, retrieves all subscriptions of given type
    get_subscription = function(vehicle_id, subscription_type, subscription_id) {
      config_data = get_config(vehicle_id);
      carvoyant_get(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
   	            config_data)
    };


    // subscription actions
    add_subscription = defaction(vehicle_id, subscription_type, params) {
      configure using ar_label = false;
      config_data = get_config(vehicle_id);
      esl = mk_subscription_esl(subscription_type);
      // see http://confluence.carvoyant.com/display/PUBDEV/NotificationPeriod
      np = params{"notification_period"} || "STATECHANGE";
      carvoyant_post(carvoyant_subscription_url(subscription_type, config_data),
      		     params.put({"postUrl": esl, "notificationPeriod": np}),
                     config_data
		    )
        with ar_label = ar_label;
    };

    del_subscription = defaction(vehicle_id, subscription_type, subscription_id) {
      configure using ar_label = false;
      config_data = get_config(vehicle_id);
      carvoyant_delete(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
                       config_data)
        with ar_label = ar_label;
    }

    // ---------- internal functions ----------
    // this should be in a library somewhere
    // eci is optional
    mk_subscription_esl = function(event_name, eci) {
      use_eci = eci || meta:eci() || "NO_ECI_AVAILABLE";
      eid = math:random(99999);
      "https://#{meta:host()}/sky/event/#{use_eci}/#{eid}/carvoyant/#{event_name}";
    };



  }

  // ---------- rules for initializing and updating vehicle cloud ----------
  rule carvoyant_init_vehicle {
    select when carvoyant init_vehicle
    pre {
      config_data = get_config();
      params = {
        "name": event:attr("name") || "Unknown Vehicle",
        "deviceId": event:attr("deviceId") || "unknown",
        "label": event:attr("label") || "My Vehicle",
        "mileage": event:attr("mileage")
      }
    }
    {
      carvoyant_post(config_data{"base_url"},
      		     params,
                     config_data
		    )
        with autoraise = "vehicle_init";
    }
  }

  rule carvoyant_update_vehicle {
    select when carvoyant update_vehicle
    pre {
      config_data = get_config(event:attr("vehicleId"));
      // will update any of the updatable data that appears in attrs() and leave the rest alone
      params = event:attrs().delete("vehicleId");
    }
    {
      carvoyant_post(config_data{"base_url"},
      		     params,
                     config_data
		    )
        with autoraise = "vehicle_update";
    }
  }

  rule initialization_ok {
    select when http post status_code  re#2\d\d#  label "vehicle_init" 
             or http post status_code  re#2\d\d#  label "vehicle_update"
    pre {

      // not sure this is actually set with the new data. If not, make a call to get()
      vehicle_data = event:attr('content').decode().pick("$.vehicle");

      storable_vehicle_data = vehicle_data.filter(function(k,v){k eq "name" || 
      			      					k eq "vehicleId" ||
								k eq "deviceId" ||
								k eq "vin" ||
								k eq "label" ||
								k eq "mileage"
                                                               })
    }
    noop();
    always {
      set ent:vehicle_data storable_vehicle_data;
      raise fuse event new_vehicle_added with 
        vehicle_data = vehicle_data
    }
  }

  
  

  // ---------- rules for managing subscriptions ----------
  rule carvoyant_add_subscription {
    select when carvoyant new_subscription_needed
    pre {
      vid = event:attr("vehicle_id") || vehicle_id();
      sub_type = event:attr("subscription_type");

      params = event:attrs()
                  .delete(["vehicle_id"])
                  .delete(["idempotent"]);
      // if idempotent attribute is set, then check to make sure no subscription of this type exist
      subs = get_subscription(vid, sub_type);
      subscribe = not event:attr("idempotent") ||
                  no_subscription(subs)
    }
    if( valid_subscription_type(sub_type) 
     && subscribe
      ) then {
        add_subscription(vid, sub_type, params) with
    	  autoraise = "add_subscription";
        send_directive("Adding subscription") with
	  attributes = event:attrs();
    }
    notfired {
      error info valid_subscription_type(sub_type) => "Already subscribed; saw " + subs.encode()
                                        	    | "Invalid Carvoyant subscription type: #{sub_type}";
    }
  }

  rule subscription_ok {
    select when http post status_code re#(2\d\d)# label "add_subscription" setting (status)
    pre {
      sub = event:attr('content').decode().pick("$.subscription");
     // new_subs = ent:subscriptions.put([sub{"id"}], sub);  // FIX
    }
    send_directive("Subscription added") with
      subscription = sub
     // always {
     //   set ent:subscriptions new_subs
     // }
  }


  rule subscription_delete {
    select when carvoyant subscription_not_needed
    {
      del_subscription(event:attr("vehicleId") || vehicle_id(), event:attr("subscription_type"), event:attr("id"))
        with ar_label = "subscription_deleted";
      send_directive("Deleting subscription") with attributes = event:attrs();
    }
  }   

  rule subscription_show {
    select when carvoyant need_vehicle_subscriptions
    pre {
      vid = event:attr("vehicle_id") || vehicle_id();
      subscriptions = get_subscription(vid, event:attr("subscription_type"));
      subs = event:attr("filter") => subscriptions{["content","subscriptions"]}
                                       .filter(function(s){ s{"deletionTimestamp"}.isnull() })
                                   | subscriptions;
    }
    send_directive("Subscriptions for #{vid} (404 means no subscriptions)") with subscriptions = subs;
  }



  // ---------- rules for handling notifications ----------

  rule ignition_status_changed is inactive { // just add select statements to appropriate rules
    select when carvoyant IGNITIONSTATUS
    pre {
      
    }
    noop();
    always {
      raise fuse event update_vehicle_data;
      raise fuse event update_trip_data if event:attr("ignitionStatus") eq "OFF"
    }
  }


  // ---------- error handling ----------
  rule carvoyant_http_fail {
    select when http post status_code re#([45]\d\d)# setting (status)
             or http put status_code re#([45]\d\d)# setting (status)
             or http delete status_code re#([45]\d\d)# setting (status)
    send_directive("Carvoyant subscription failed") with
       sub_status = event:attrs();
    fired {
      error warn "Carvoyant HTTP Error (#{status}): ${event:attr('status_line')}. Autoraise label: #{event:attr('label')}."
    }
  }



}