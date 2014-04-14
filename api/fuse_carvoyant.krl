ruleset fuse_carvoyant {
  meta {
    name "Fuse Carvoyant Ruleset"
    author "Phil Windley"
    description <<
Provides rules for handling Carvoyant events
>>

    sharing on   // turn off after debugging

    use module b16x10 alias fuse_keys
      with foo = 1

    use module a169x625 alias CloudOS
    use module a169x676 alias pds
    use module b16x19 alias common

    errors to b16x13

    provides namespace, vehicle_id, get_config, carvoyant_headers, carvoyant_vehicle_data, get_vehicle_data, 
             vehicleStatus, keyToLabel, tripInfo,
             get_subscription,no_subscription, add_subscription, del_subscription, get_eci_for_carvoyant

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

    data_labels = {
		  "GEN_DTC"          : "Diagnostic Trouble Codes" ,
		  "GEN_VOLTAGE"      : "Battery Voltage" ,
		  "GEN_TRIP_MILEAGE" : "Trip Mileage (last trip)" ,
		  "GEN_ODOMETER"     : "Vehicle Reported Odometer" ,
		  "GEN_WAYPOINT"     : "GPS Location" ,
		  "GEN_HEADING"      : "Heading" ,
		  "GEN_RPM"          : "Engine Speed" ,
		  "GEN_FUELLEVEL"    : "% Fuel Remaining" ,
		  "GEN_FUELRATE"     : "Rate of Fuel Consumption" ,
		  "GEN_ENGINE_COOLANT_TEMP" : "Engine Coolant Temperature" ,
		  "GEN_SPEED"        : "Maximum Speed Recorded (last trip)"
		};

    keyToLabel = function(key) {
      data_labels{key};
    };

    namespace = function() {
      "fuse:carvoyant";
    };

    vehicle_id = function() {
      config = pds:get_item(namespace(), "config");
      config{"deviceID"} // old name remove once we are creating vehicles with new name
     ||
      config{"deviceId"}
     ||
      pds:get_item(namespace(), "vehicle_info").pick("$.vehicleId")
    };


    // vehicle_id is optional if creating a new vehicle profile
    // key is optional, if missing, use default
    get_config = function(vid, key) {
       carvoyant_config_key = key || namespace();
       config_data = pds:get_item(carvoyant_config_key, "config") || {};

       vid = vid
          || config_data{"deviceID"} // old name remove once we are creating vehicles with new name
          || config_data{"deviceId"};
       hostname = "dash.carvoyant.com";
       url = "https://#{hostname}/api/vehicle/#{vid}";
       config_data
         .put({"hostname": hostname,
	       "base_url": url,
	       "vehicle_id": vid,
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
    carvoyant_vehicle_data = function(vid) {
      vid = vid || vehicle_id();
      config_data = get_config(vid);
      carvoyant_get(config_data{"base_url"}, config_data);
    };

    get_vehicle_data = function (vehicle_data, vehicle_number, dkey) {
      vda = vehicle_data{["content","vehicle"]};
      vd = vehicle_number.isnull() => vda | vda[vehicle_number];
      dkey.isnull() => vd | vd{dkey}
    };

    vehicleStatus = function(vid) {
      vid = vid || vehicle_id();
      config_data = get_config(vid);
      result = carvoyant_get(config_data{"base_url"}+"/data?mostRecentOnly=true", config_data);
      result{"status_code"} eq "200" => result{["content","data"]}
       			       	     	  .collect(function(v){v{"key"}}) // turn array into map of arrays
					  // get rid of arrays and replace with value plus label
                           		  .map(function(k,v){v[0].put(["label"],keyToLabel(k))})
                                      | mk_error(result);
    };

    // ---------- trips ----------
    // vid is optional
    tripInfo = function(tid, vid) {
      config_data = get_config(vid);
      trip_url = config_data{"base_url"} + "/trip/#{tid}";
      result = carvoyant_get(trip_url, config_data);
      result{"status_code"} eq "200" => result{["content","trip"]}
                                      | mk_error(result)
    }

    mk_error = function(res) { // let's try the simple approach first
      res
    }

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
    add_subscription = defaction(vid, subscription_type, params) {
      configure using ar_label = false;
      config_data = get_config(vid);
      esl = mk_subscription_esl(subscription_type);
      // see http://confluence.carvoyant.com/display/PUBDEV/NotificationPeriod
      np = params{"notification_period"} || "STATECHANGE";
      carvoyant_post(carvoyant_subscription_url(subscription_type, config_data),
      		     params.put({"postUrl": esl, "notificationPeriod": np}),
                     config_data
		    )
        with ar_label = ar_label;
    };

    del_subscription = defaction(subscription_type, subscription_id, vid) {
      configure using ar_label = false;
      config_data = get_config(vid);
      carvoyant_delete(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
                       config_data)
        with ar_label = ar_label;
    }

    // ---------- internal functions ----------
    // this should be in a library somewhere
    // eci is optional
    mk_subscription_esl = function(event_name, eci) {
      use_eci = eci || get_eci_for_carvoyant() || "NO_ECI_AVAILABLE"; 
      eid = math:random(99999);
      "https://#{meta:host()}/sky/event/#{use_eci}/#{eid}/carvoyant/#{event_name}";
    };

    // creates a new ECI (once) for carvoyant
    get_eci_for_carvoyant = function() {
      carvoyant_channel_name = "carvoyant-channel";
      current_channels = CloudOS:channelList();
      carvoyant_channel = current_channels{"channels"}.filter(function(x){x{"name"} eq carvoyant_channel_name});
      carvoyant_channel.length() > 0 => carvoyant_channel.head().pick("$.cid")
                                      | CloudOS:channelCreate(carvoyant_channel_name).pick("$.token")
    }


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
    pre {
      sub_type =  event:attr("subscription_type");
      id = event:attr("id");
    }
    if valid_subscription_type(sub_type) then
    {
      del_subscription(sub_type, id, null)
        with ar_label = "subscription_deleted";
      send_directive("Deleting subscription") with attributes = event:attrs();
    }
    notfired {
      error info "Invalid Carvoyant subscription type: #{sub_type} for #{id}";
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

  rule clean_up_subscriptions {
    select when carvoyant dirty_subscriptions
    foreach get_subscription().pick("$..subscriptions").filter(function(s){ s{"deletionTimestamp"}.isnull() }) setting(sub)
    pre {
      id = sub{"id"};	
      sub_type = sub{"_type"};
      postUrl = sub{"postUrl"};
      my_current_eci = get_eci_for_carvoyant();
    }
    if(not postUrl.match("re#/#{my_current_eci}/#".as("regexp"))) then
    {
      send_directive("Will delete subscription #{id} with type #{sub_type}") with
        sub_value = sub;
      del_subscription(sub_type, id, null)
        with ar_label = "subscription_deleted";
    }
  }


  // ---------- rules for handling notifications ----------

  rule ignition_status_changed  { 
    select when carvoyant ignitionStatus
    pre {

      status = event:attr("ignitionStatus");
      tid = event:attr("tripId");
    }
    noop();
    always {
      raise fuse event need_vehicle_data;
      raise fuse event new_trip with tripId = tid if status eq "OFF";
    }
  }

  rule lowBattery_status_changed  { 
    select when carvoyant lowBattery
    pre {
      threshold = event:attr("thresholdVoltage");
      recorded = event:attr("recordedVoltage");
    }
    noop();
    always {
      log "Recorded battery level: " + recorded;
      raise pds event new_data_available
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "lowBattery_fired",
	    "value": event:attrs()
	              .delete(["_generatedby"]),
            "_api": "sky"
 		   
	  };
      raise fuse event updated_battery
	  with threshold = threshold
	   and recorded = recorded
	   and timestamp = event:attr("_timestamp");

    }
  }

  rule dtc_status_changed  { 
    select when carvoyant troubleCode
    pre {
      codes = event:attr("troubleCodes");
    }
    noop();
    always {
      log "Recorded trouble codes: " + codes.encode();
      raise pds event new_data_available
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "troubleCode_fired",
	    "value": event:attrs()
	              .delete(["_generatedby"]),
            "_api": "sky"
 		   
	  };
     raise fuse event updated_dtc
	  with dtc = codes
	   and timestamp = event:attr("_timestamp");
    }
  }

  rule fuel_level_low  { 
    select when carvoyant numericDataKey dataKey "GEN_FUELLEVEL"
    pre {
      threshold = event:attr("thresholdValue");
      recorded = event:attr("recordedValue");
      relationship = event:attr("relationship");
    }
    noop();
    always {
      log "Fuel level of #{recorded}% is #{relationship.lc()} threshold value of #{threshold}%";
      raise pds event new_data_available
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "fuelLevel_fired",
	    "value": event:attrs()
	              .delete(["_generatedby"]),
            "_api": "sky"
 		   
     };
     raise fuse event updated_fuel_level
       with threshold = threshold
	and recorded = recorded
	and timestamp = event:attr("_timestamp");
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