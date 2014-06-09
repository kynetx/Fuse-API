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
    use module b16x17 alias fleet

    errors to b16x13

    provides clientAccessToken, codeForAccessToken, refreshTokenForAccessToken, showTokens, // don't provide after debug
             is_authorized, carvoyantOauthUrl,
             namespace, vehicle_id, get_config, carvoyant_headers, carvoyant_vehicle_data, get_vehicle_data, 
	     carvoyantVehicleData,
             vehicleStatus, keyToLabel, tripInfo,
             get_subscription, no_subscription, add_subscription, del_subscription, get_eci_for_carvoyant

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

    api_hostname = "api.carvoyant.com";
    apiHostname = function() {api_hostname};
    api_url = "https://"+api_hostname+"/v1/api";
    oauth_url = "https://"+api_hostname+"/oauth/token";
    apiUrl = function() { api_url };

    // ---------- authorization ----------

    showTokens = function() {
      ent:account_info
    }

    carvoyantOauthUrl = function(redirect_uri, accessing_eci) {
    
      params = {"client_id" : keys:carvoyant_client("client_id"),	
                "redirect_uri" : redirect_uri,
		"response_type" : "code",
		"state": [meta:rid(), accessing_eci ].join(",")
		};

// &state=b16x11,02F3F3EA-DC82-11E3-9FD7-CEEAE71C24E1

      query_string = params.map(function(k,v){k+"="+v}).values().join("&").klog(">>>>> query string >>>>>>");
      "https://auth.carvoyant.com/OAuth/authorize?" + query_string
    
    }

    // used for getting token to create an account; not for general use
    clientAccessToken = function() {
      header = 
            {"credentials": {
               "username": keys:carvoyant_client("client_id"),
               "password": keys:carvoyant_client("client_secret"),
	       "realm": apiHostname(),
	       "netloc": apiHostname() + ":443"
               },
             "params" : {"grant_type": "client_credentials"}
            }; //.klog(">>>>>> client header <<<<<<<<");
      raw_result = http:post(oauth_url, header);
      (raw_result{"status_code"} eq "200") => raw_result{"content"}.decode()
                                            | raw_result.decode()
    };

    is_authorized = function() {

      created = ent:account_info{"timeStamp"};
      time_expires = time:add(created, {"seconds": ent:account_info{"expires_in"}});
      expired = time:compare(time_expires,
                             time:now()) // less than 1 if expired
                < 1;      

//      access_token = expired => refreshTokenForAccessToken() | ent:access_token;

      vehicle_info = expired => {} | carvoyant_get(api_url+"/vehicle/");
      vehicle_info{"status_code"} eq "200"
    };

    codeForAccessToken = function(code, redirect_uri) {
      header = 
            {"credentials": {
               "username": keys:carvoyant_client("client_id"),
               "password": keys:carvoyant_client("client_secret"),
	       "realm": apiHostname(),
	       "netloc": apiHostname() + ":443"
               },
             "params" : {"grant_type": "authorization_code",
	                 "code": code,
			 "redirect_uri": redirect_uri
	                }
            }.klog(">>>>>> client header <<<<<<<<");
      raw_result = http:post(oauth_url, header);
      (raw_result{"status_code"} eq "200") => raw_result{"content"}.decode()
                                            | raw_result.decode()
    };


    refreshTokenForAccessToken = function() {
      header = 
            {"credentials": {
               "username": keys:carvoyant_client("client_id"),
               "password": keys:carvoyant_client("client_secret"),
	       "realm": apiHostname(),
	       "netloc": apiHostname() + ":443"
               },
             "params" : {"grant_type": "refresh_token",
	                 "refresh_token": ent:account_info{"refresh_token"}
	                }
            }.klog(">>>>>> client header <<<<<<<<");
      raw_result = http:post(oauth_url, header);
      (raw_result{"status_code"} eq "200") => raw_result{"content"}.decode()
                                            | raw_result.decode()
    };


    // ---------- config ----------

    // vehicle_id is optional if creating a new vehicle profile
    // key is optional, if missing, use default
    get_config = function(vid, key) {
       carvoyant_config_key = key || namespace();
       config_data = pds:get_item(carvoyant_config_key, "config") || {};
        // vid = vid
        //    || config_data{"deviceID"} // old name remove once we are creating vehicles with new name
        //    || config_data{"deviceId"};
       base_url = api_url+ "/vehicle/";
       url = base_url + vid;
       config_data
         .put({"hostname": api_hostname,
	       "base_url": url,
	       "vehicle_id": vid,
	       "access_token" : ent:access_token
	      })
    }

    // ---------- general carvoyant API access functions ----------
    // See http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism for details

    // params is optional
     // carvoyant_headers = function(config_data, params) {
     //   {"credentials": {
     //       "username": config_data{"apiKey"},
     //       "password": config_data{"secToken"},
     //       "realm": "Carvoyant API",
     //       "netloc": config_data{"hostname"} + ":443"
     //       },
     //    "params" : params || {}
     //   }
     // };
    
    oauthHeader = function(access_token) {
      {"Authorization": "Bearer " + access_token.klog(">>>>>> using access token >>>>>>>"),
       "content-type": "application/json"
      }
    }

    // functions
    // params if optional
    carvoyant_get = function(url, config_data, params) {
      raw_result = http:get(url, 
                            params, 
			    oauthHeader(config_data{"access_token"}),
			    ["WWW-Authenticate"]
			   );
      (raw_result{"status_code"} eq "200") => {"content" : raw_result{"content"}.decode(),
                                               "status_code": raw_result{"status_code"}
                                              }
                                            | raw_result.klog(">>>>>>> carvoyant_get() error >>>>>>")
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
      auth_data =  carvoyant_headers(config_data);
      http:put(url)
        with body = payload
	 and headers = oauthHeader(config_data{"access_token"})
         and autoraise = ar_label;
         // with credentials = auth_data{"credentials"} 
         //  and params = params
         //  and autoraise = ar_label;
    };

    carvoyant_delete = defaction(url, config_data) {
      configure using ar_label = false;
      http:delete(url) 
        with headers = oauthHeader(config_data{"access_token"})
         and autoraise = ar_label; 
       // auth_data =  carvoyant_headers(config_data);
       //   with credentials = auth_data{"credentials"} 
       //    and autoraise = ar_label;
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
                                             | mk_error(data);
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

  // ---------- create account ----------

  /*
    I'm going to just get new client credentials each time. If we get to where we're adding 100's of account per week 
    we may want to rethink this, store them, use the refresh, etc. 
  */
  // running this in fleet...
  rule init_account {
    select when carvoyant init_account
    pre {
      client_access_token = clientAccessToken();
    }
    if(client_access_token{"access_token"})  then 
    {
      send_directive("Retrieved access token for client_credentials")
    }
    fired {
      raise explicit event "need_carvoyant_account"
        attributes event:attrs().put(["access_token"], client_access_token{"access_token"})
    } else {
      error warn "Carvoyant Error: " + client_access_token.encode()
    }
  }


  rule init_account_follow_on {
    select when explicit need_carvoyant_account
    pre {

      owner = CloudOS:subscriptionList(common:namespace(),"FleetOwner").head().pick("$.eventChannel");
      profile = common:skycloud(owner,"pds","get_all_me");
//      profile = pds:get_all_me();
      first_name = event:attr("first_name") || profile{"myProfileName"}.extract(re/^(\w+)\s*/).head() || "";
      last_name = event:attr("last_name") || profile{"myProfileName"}.extract(re/\s*(\w+)$/).head() || "";
      email = event:attr("email") || profile{"myProfileEmail"} || "";
      phone = event:attr("phone") || profile{"myProfilePhone"} || "8015551212";
      zip = event:attr("zip") || profile{"myProfileZip"} || "84042";
      username = event:attr("username") || "";
      password = event:attr("password") || "";

      payload = { "firstName": first_name,  
                  "lastName": last_name,  
		  "email": email,  
		  "zipcode": zip || "84042",  
		  "phone": phone,  
		  "timeZone": null,  
		  "preferredContact": "EMAIL",  
		  "username" : username,  
		  "password": password
		};

      bearer = event:attr("access_token");

      url = (api_url+"/account/").klog(">>>>>> url <<<<<<<<<<");

    }

    if( username neq "" 
     && password neq ""
      ) then 
    {
      //post to carvoyant
      http:post(url) 
        with body = payload
	 and headers = {"content-type": "application/json",
	                "Authorization": "Bearer " + bearer
	               }
         and autoraise = "account_init";

      send_directive("Posting to Carvoyant to make account") with 
        username = payload 
      
    }
    fired {
      log ">>>>> creating carvoyant account <<<<<"
    } else {
      error warn "Must supply username and password" ;
    }

  } 

  rule process_carvoyant_acct_creation {
    select when http post status_code  re#2\d\d#  label "account_init"
    pre {
      account = event:attr('content').decode().pick("$.account");
      account_id = account{"id"};
      code = account{["accessToken", "code"]}.klog(">>>> code >>>> ");
      tokens = codeForAccessToken(code, "https://kibdev.kobj.net/sky/event/somethingelsegoeshere");
    }

    {
      send_directive("Exchanged account code for account tokens") with tokens = tokens
    }
    fired {
      raise carvoyant event new_tokens_available with tokens = tokens.put(["timeStamp"], time:now())
      // set ent:account_info tokens.put(["timeStamp"], time:now()); // includes refresh token
      // set ent:access_token tokens{"access_token"};
    }
  }

  rule error_carvoyant_acct_creation {
    select when http post status_code  re#[45]\d\d#  label "account_init"

    always {
      log ">>>>> carvoyant account creation failed " + event:attrs().encode();
    }

  }

  rule retry_refresh_token {
    select when http post status_code re#401# label "???" // check error number and header...
    pre {
      tokens = refreshTokenForAccessToken();
    }
    if( tokens{"error"}.isnull() ) then 
    {
      send_directive("Used refresh token to get new account token");
    }
    fired {
      raise carvoyant event new_tokens_available with tokens = tokens.put(["timeStamp"], time:now())
       // set ent:account_info tokens.put(["timeStamp"], time:now()); // includes refresh token
       // set ent:access_token tokens{"access_token"};
    } else {
      log(">>>>>>> couldn't use refresh token to get new access token <<<<<<<<");
      log(">>>>>>> we're screwed <<<<<<<<");
    }
  }

  rule update_token {
    select when carvoyant access_token_expired

    pre {
      tokens = refreshTokenForAccessToken();
    }
    if( tokens{"error"}.isnull() ) then 
    {
      send_directive("Used refresh token to get new account token");
      // send to each vehicle...
    }
    fired {
      raise carvoyant event new_tokens_available with tokens = tokens.put(["timeStamp"], time:now())
       // set ent:account_info tokens.put(["timeStamp"], time:now()); // includes refresh token
       // set ent:access_token tokens{"access_token"};
    } else {
      log(">>>>>>> couldn't use refresh token to get new access token <<<<<<<<");
    }
    
  }
  
  // used by both fleet and vehicle to store tokens
  rule store_tokens {
    select when carvoyant new_tokens_available
    pre {
      tokens = event:attr("tokens").decode();
    }
    if( not tokens.isnull() ) then 
    {
      send_directive("Storing new tokens");
      // send to each vehicle...
    }
    fired {
      set ent:account_info tokens; // includes refresh token
      set ent:access_token tokens{"access_token"};
    } else {  
      log(">>>>>>> tokens empty <<<<<<<<");
    }
  }

  // this needs to be in fleet carvoyant ruleset, not vehicle
  rule send_vehicle_new_config {
    select when fuse config_outdated
    foreach fleet:vehicleChannels().pick("$..channel") setting (vehicle_channel)
    {
      send_directive("Sending Carvoyant config to " + vehicle_channel) with 
	tokens = ent:account_info; 
      event:send({"cid": vehicle_channel}, "carvoyant", "new_tokens_available") with
        attrs = {"tokens": ent:account_info.encode()
	        };
    }
  }



  // ---------- rules for initializing and updating vehicle cloud ----------


  rule carvoyant_init_vehicle {
    select when carvoyant init_vehicle
    pre {
      config_data = get_config(""); // pass in empty vid to ensure we create one
      profile = pds:get_all_me();
      params = {
        "name": event:attr("name") || profile{"myProfileName"} || "Unknown Vehicle",
        "deviceId": vehicle_id() || event:attr("deviceId") || "unknown",
        "label": event:attr("label") || profile{"myProfileName"} || "My Vehicle",
	"vin": event:attr("vin") || profile{"myVin"} || "unknown",
        "mileage": event:attr("mileage") || "10"
      }
    }
    if( params{"deviceId"} neq "unknown"
     && params{"vin"} neq "unknown"
      ) then
    {
      send_directive("Initializing Carvoyant account for vehicle ") with params = params;
      carvoyant_post(config_data{"base_url"},
      		     params,
                     config_data
   	    )
        with ar_label = "vehicle_init";
    }
    fired {
      log(">>>>>>>>>> initializing Carvoyant account with device ID = " + params{"deviceId"});
      raise carvoyant event new_device_id 
        with deviceId = deviceId
    } else {
      log(">>>>>>>>>> Carvoyant account initializaiton failed; missing device ID");
    }
  }

  // this neds work
  rule carvoyant_update_vehicle_account {
    select when carvoyant update_account
    pre {
      // if this vehicleId attr is unset, this creates a new vehicle...
      config_data = get_config(event:attr("vehicleId")); 
      deviceId = event:attr("deviceId");
      // will update any of the updatable data that appears in attrs() and leave the rest alone
      params = event:attrs().delete(["vehicleId"]);
    }
    {
      send_directive("Updating Carvoyant account for vehicle ");
      carvoyant_post(config_data{"base_url"},
      		     params,
                     config_data
		    )
        with ar_label = "vehicle_account_update";
    }
    fired {
      raise carvoyant event new_device_id 
        with deviceId = deviceId if not deviceId.isnull()
    }
  }


  rule store_device_id {
    select when carvoyant new_device_id
    pre {
      deviceId = event:attr("deviceId") ;

    }
    if (not deviceId.isnull() ) then {
      noop();
    }
    fired {
      raise pds event "new_data_available"
	  attributes {
	    "namespace": namespace(),
	    "keyvalue": "config",
	    "value": {"deviceId": deviceId
	             },
            "_api": "sky"
 		   
	  };
    }
  }

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



}