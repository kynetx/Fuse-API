ruleset fuse_carvoyant {
  meta {
    name "Fuse Carvoyant Ruleset"
    author "Phil Windley"
    description <<
Provides rules for handling Carvoyant events. Modified for the Mashery API
>>

    sharing on   // turn off after debugging

    use module b16x10 alias fuse_keys
      with foo = 1

    use module a169x625 alias CloudOS
    use module a169x676 alias pds
    use module b16x19 alias common
    use module b16x23 alias carvoyant_oauth

    errors to b16x13

    provides namespace, vehicle_id, get_config, carvoyant_headers, carvoyant_vehicle_data, get_vehicle_data, 
	     carvoyantVehicleData, isAuthorized,
             vehicleStatus, keyToLabel, tripInfo,
             getSubscription, no_subscription, add_subscription, del_subscription, get_eci_for_carvoyant

  }

  global {

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

    // appears in both this ruleset and fuse_fleet_oauth
    namespace = function() {
      "fuse:carvoyant";
    };

    vehicle_id = function() {
      config = pds:get_item(namespace(), "config") || {}; // can delete after vehicles are updated
      me = pds:get_me("deviceId"); 
      config{"deviceId"}
     ||
      me
     ||
      pds:get_item(namespace(), "vehicle_info").pick("$.vehicleId")
    };

    api_hostname = "api.carvoyant.com";
    apiHostname = function() {api_hostname};
    api_url = "https://"+api_hostname+"/v1/api";
    apiUrl = function() { api_url };


    // ---------- config ----------

    getTokensFromFleet = function() {
       my_fleet = CloudOS:subscriptionList(common:namespace(),"Fleet").head();
       common:skycloud(my_fleet{"eventChannel"},"b16x23","getTokens", {"id": my_fleet{"channelName"}});
    }

    // if we're the fleet, we ask the module installed here, if not, ask the fleet
    getTokens = function() {
      my_type = pds:get_item("myCloud", "mySchemaName").klog(">>> my type >>>>");
      (my_type eq "Fleet") => carvoyant_oauth:getTokens()
                            | getTokensFromFleet()
    }

    // vehicle_id is optional if creating a new vehicle profile
    // key is optional, if missing, use default
    get_config = function(vid, key) {
       carvoyant_config_key = key || namespace();
       config_data = {"deviceId": vehicle_id() || "no device found"};
       base_url = api_url+ "/vehicle/";
       url = base_url + vid;
       account_info = getTokens();
       config_data
         .put({"hostname": api_hostname,
	       "base_url": url,
	       "access_token" : account_info{"access_token"}			  
	      })
    }

    isAuthorized = function() {
      account_info = getTokens();
      created = account_info{"timestamp"} || time:now(); 
      expires_in =  account_info{"expires_in"} || -1 ; // if we don't find it, it's expired
      time_expires = time:add(created, {"seconds": expires_in});
      expired = time:compare(time_expires,
                             time:now()) // less than 1 if expired
                < 1;      
//      access_token = expired => refreshTokenForAccessToken() | account_info{"access_token"};

      config_data = get_config();
      vehicle_info = expired => {} | carvoyant_get(api_url+"/vehicle/", config_data) || {};
      {"authorized" : vehicle_info{"status_code"} eq "200"}
    };



    // ---------- general carvoyant API access functions ----------
    // See http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism for details
    oauthHeader = function(access_token) {
      {"Authorization": "Bearer " + access_token.klog(">>>>>> using access token >>>>>>>"),
       "content-type": "application/json"
      }
    }

    // functions
    // params if optional
    carvoyant_get = function(url, config_data, params, redo) {
      raw_result = http:get(url, 
                            params, 
			    oauthHeader(config_data{"access_token"}),
			    ["WWW-Authenticate"]
			   );
      (raw_result{"status_code"} eq "200") => {"content" : raw_result{"content"}.decode(),
                                               "status_code": raw_result{"status_code"}
                                              } |
      (raw_result{"status_code"} eq "401") &&
      redo.isnull()                        => fix_token(raw_result, url, config_data, params) 
                                            | raw_result.klog(">>>>>>> carvoyant_get() error >>>>>>")
                  
    };

    fix_token = function(result, url, config_data, param) {
      account_info = getTokens();
      try_refresh = not account_info{"refresh_token"}.isnull();
      new_tokens = try_refresh => carvoyant_oauth:refreshTokenForAccessToken().klog(">>>>> refreshing for carvoyant_get() >>> ")
                                | {};
      new_tokens{"access_token"} => carvoyant_get(url, 
                                                  config_data.put(["access_token"], new_tokens{"access_token"}),
						  params,
						  true
                                                 )
                                  | result.put(["refresh_token_tried"], try_refresh).klog(">>>> giving up on fix token ")
    };

    // actions
    carvoyant_post = defaction(url, payload, config_data) { // updated for Mashery
      configure using ar_label = false;

      // check and update access token???? How? 

      //post to carvoyant
      http:post(url) 
        with body = payload
	 and headers = oauthHeader(config_data{"access_token"})
         and autoraise = ar_label.klog(">>>>> autoraise label >>>>> ");
    };

    carvoyant_put = defaction(url, params, config_data) {
      configure using ar_label = false;
      http:put(url)
        with body = payload
	 and headers = oauthHeader(config_data{"access_token"})
         and autoraise = ar_label;
    };

    carvoyant_delete = defaction(url, config_data) {
      configure using ar_label = false;
      http:delete(url) 
        with headers = oauthHeader(config_data{"access_token"})
         and autoraise = ar_label; 
    };


    // ---------- vehicle data ----------
    // without vid, returns data on all vehicles in account
    carvoyant_vehicle_data = function(vid) {
      vid = vid || vehicle_id();
      config_data = get_config(vid);
      carvoyant_get(config_data{"base_url"}, config_data);
    };

    get_vehicle_data = function (vehicle_data, vehicle_number, dkey) {
      vda = vehicle_data{["content","vehicle"]} || {};
      vd = vehicle_number.isnull() => vda | vda[vehicle_number];
      dkey.isnull() => vd | vd{dkey}
    };

    carvoyantVehicleData = function(vid) {
      vid = vid || vehicle_id();
      config_data = get_config(vid);
      data = carvoyant_get(config_data{"base_url"}, config_data);
      status = data{"status_code"} eq "200" => data{["content","vehicle"]}
                                             | []
      status
    }

    vehicleStatus = function(vid) {
      vid = vid || vehicle_id();
      config_data = get_config(vid);
      most_recent = carvoyant_get(config_data{"base_url"}+"/data?mostRecentOnly=true", config_data);
      status = 
        most_recent{"status_code"} eq "200" => most_recent{["content","data"]}
         			       	     	  .collect(function(v){v{"key"}}) // turn array into map of arrays
 					          // get rid of arrays and replace with value plus label
                           		          .map(function(k,v){v[0].put(["label"],keyToLabel(k))})
                                             | mk_error(most_recent);
      status
    };


    // ---------- trips ----------
    // vid is optional
    tripInfo = function(tid, vid) {
      config_data = get_config(vid).klog(">>> Config data in tripInfo >>>>>");
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
    getSubscription = function(vehicle_id, subscription_type, subscription_id) {
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


  // ---------- for retries from posting... ----------

  rule retry_refresh_token {
    select when http post status_code re#401# label "???" // check error number and header...
    pre {
      tokens = carvoyant_oauth:refreshTokenForAccessToken(); // mutates ent:account_info
    }
    if( tokens{"error"}.isnull() ) then 
    {
      send_directive("Used refresh token to get new account token");
    }
    fired {
      raise carvoyant event new_tokens_available with tokens = getTokens() //ent:account_info
    } else {
      log(">>>>>>> couldn't use refresh token to get new access token <<<<<<<<");
      log(">>>>>>> we're screwed <<<<<<<<");
    }
  }


  // ---------- rules for initializing and updating vehicle cloud ----------

  // creates and updates vehicles in the Carvoyant system
  rule carvoyant_init_vehicle {
    select when carvoyant init_vehicle
             or pds profile_updated
    pre {
      cv_vehicles = carvoyantVehicleData().klog(">>>>> carvoyant vehicle data >>>>") || [];
      profile = pds:get_all_me().klog(">>>>> profile >>>>>");
      // true if vehicle exists in Carvoyant with same vin and deviceId and not yet linked
      vehicle_match = cv_vehicles
                        .filter(function(v){
			          v{"vin"} eq profile{"vin"}  
                               && v{"deviceId"} eq profile{"deviceId"}
			       && ent:vehicle_data{"vehicleId"}.isnull()
                               }).klog(">>>> matching vehicles >>>>").length() 
                      > 0;
      vid = vehicle_match                  => profile{"deviceId"} 
          | event:name() eq "init_vehicle" => "" // pass in empty vid to ensure we create one
          |                                   ent:vehicle_data{"vehicleId"} || profile{"deviceId"};
      config_data = get_config(vid).klog(">>>>> config data >>>>>"); 
      params = {
        "name": event:attr("name") || profile{"myProfileName"} || "Unknown Vehicle",
        "deviceId": event:attr("deviceId") || profile{"deviceId"} || "unknown",
        "label": event:attr("label") || profile{"myProfileName"} || "My Vehicle",
	"vin": event:attr("vin") || profile{"vin"} || "unknown",
        "mileage": event:attr("mileage") || profile{"mileage"} || "10"
      }.klog(">>>> creating vehicle with these params >>>> ")
    }
    if( params{"deviceId"} neq "unknown"
     && params{"vin"} neq "unknown"
      ) then
    {
      send_directive("Initializing or updating Carvoyant vehicle for Fuse vehicle ") with params = params;
      carvoyant_post(config_data{"base_url"},
      		     params,
                     config_data
   	    )
        with ar_label = "vehicle_init";
    }
    fired {
      log(">>>>>>>>>> initializing Carvoyant account with device ID = " + params{"deviceId"});
      raise fuse event vehicle_uninitialized if vehicle_match || event:name() eq "init_vehicle";
    } else {
      log(">>>>>>>>>> Carvoyant account initializaiton failed; missing device ID");
    }
  }

  // this needs work
   // rule carvoyant_update_vehicle_account {
   //   select when carvoyant update_account
   //   pre {
   //     // if this vehicleId attr is unset, this creates a new vehicle...
   //     config_data = get_config(event:attr("vehicleId")); 
   //     deviceId = event:attr("deviceId");
   //     // will update any of the updatable data that appears in attrs() and leave the rest alone
   //     params = event:attrs().delete(["vehicleId"]);
   //   }
   //   {
   //     send_directive("Updating Carvoyant account for vehicle ");
   //     carvoyant_post(config_data{"base_url"},
   //     		     params,
   //                    config_data
   // 		    )
   //       with ar_label = "vehicle_account_update";
   //   }
   //   fired {
   //     raise carvoyant event new_device_id 
   //       with deviceId = deviceId if not deviceId.isnull()
   //   }
   // }



  rule initialization_ok { 
    select when http post status_code  re#2\d\d#  label "vehicle_init" 
             or http post status_code  re#2\d\d#  label "vehicle_account_update"
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
      raise fuse event "vehicle_account_updated" with 
        vehicle_data = vehicle_data;
      raise carvoyant event new_device_id 
        with deviceId = "BAD DEVICE ID" if deviceId.isnull()
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
      subs = getSubscription(vid, sub_type);
      subscribe = not event:attr("idempotent") ||
                  no_subscription(subs)
    }
    if( valid_subscription_type(sub_type) 
     && subscribe
      ) then {
        add_subscription(vid, sub_type, params) with
    	  ar_label = "add_subscription";
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
      subscriptions = getSubscription(vid, event:attr("subscription_type"));
      subs = event:attr("filter") => subscriptions{["content","subscriptions"]}
                                       .filter(function(s){ s{"deletionTimestamp"}.isnull() })
                                   | subscriptions;
    }
    send_directive("Subscriptions for #{vid} (404 means no subscriptions)") with subscriptions = subs;
  }

  rule clean_up_subscriptions {
    select when carvoyant dirty_subscriptions
    foreach getSubscription().pick("$..subscriptions").filter(function(s){ s{"deletionTimestamp"}.isnull() }) setting(sub)
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
      raise fuse event "need_vehicle_data";
      raise fuse event "need_vehicle_status";
      raise fuse event "new_trip" with tripId = tid if status eq "OFF";
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
      raise pds event "new_data_available"
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "lowBattery_fired",
	    "value": event:attrs()
	              .delete(["_generatedby"]),
            "_api": "sky"
 		   
	  };
      raise fuse event "updated_battery"
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
      raise pds event "new_data_available"
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "troubleCode_fired",
	    "value": event:attrs()
	              .delete(["_generatedby"]),
            "_api": "sky"
 		   
	  };
     raise fuse event "updated_dtc"
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
      raise pds event "new_data_available"
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "fuelLevel_fired",
	    "value": event:attrs()
	              .delete(["_generatedby"]),
            "_api": "sky"
 		   
     };
     raise fuse event "updated_fuel_level"
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
      error warn "Carvoyant HTTP Error (#{status}): #{event:attr('status_line')}. Autoraise label: #{event:attr('label')}."
    }
  }


// fuse_carvoyant_mashery.krl
}
