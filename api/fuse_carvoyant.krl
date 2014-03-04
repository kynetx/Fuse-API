ruleset fuse_carvoyant {
  meta {
    name "Fuse Carvoyant Ruleset"
    author "Phil Windley"
    description <<
Provides rules for handling Carvoyant events
>>

    use module b16x10 alias fuse_keys

    errors to a16xSomeValidRID
  
  }

  global {

    // config data contains
    //   deviceID - Carvoyant device ID
    //   apiKey - API Key in http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism
    //   secToken - Access Token in http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism 

    // [TODO] 
    //  vehicle ID can't be in config data. Has to match one of them, but is supplied


    // key is optional, if missing, use default
    get_config = function(key) {
       carvoyant_config_key = key || "fuse:carvoyant";
       hostname = "dash.carvoyant.com";
       config_data = pds:get_items(carvoyant_config_key);
       url = "https://#{hostname}/api/vehicle/"+ config_data{"deviceID"}
       config_data
         .put({"hostname": hostname,
	       "base_url": url
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
      http:get(url, carvoyant_headers(config_data))
    };

    // actions
    carvoyant_post = defaction(url, params, config_data) {
      configure using autoraise = false;
      http:post(url, carvoyant_headers(config_data, params))
        with autoraise = autoraise;
    };

    carvoyant_put = defaction(url, params, config_data) {
      configure using autoraise = false;
      http:put(url, carvoyant_headers(config_data, params))
        with autoraise = autoraise;
    };

    carvoyant_delete = defaction(url, config_data) {
      configure using autoraise = false;
      http:delete(url, carvoyant_headers(config_data)) 
        with autoraise = autoraise;
    };

    // ---------- subscriptions ----------
    carvoyant_subscription_url = function(subscription_type, config_data, subscription_id) {
       base_url = config_data{"base_url"} + "/eventSubscription/" + subsciption_type;
       subscription_id.isnull() => base_url 
	                         | base_url + "/" + subscription_id
    };

    valid_carvoyant_subscription = function(sub_type) {
      valid_types = {"geofence": true,
                     "lowbattery": true,
		     "numericdatakey": true,
		     "timeofday": true,
		     "troublecode": true
      };
      not valid_types{sub_type}.isnull()
    }

    // subscription functions
    // subscription_id is optional, if left off, retrieves all subscriptions of given type
    cavoyant_get_subscription = function(subscription_type, subscription_id) {
      config_data = get_config();
      carvoyant_get(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
   	            config_data)
    };


    // subscription actions
    cavoyant_add_subscription = defaction(subscription_type, params) {
      configure using autoraise = false;
      config_data = get_config();
      carvoyant_post(carvoyant_subscription_url(subscription_type, config_data),
                     config_data,
	             params)
        with autoraise = autoraise;
    };

    cavoyant_del_subscription = defaction(subscription_type, subscription_id) {
      configure using autoraise = false;
      config_data = get_config();
      carvoyant_delete(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
                       config_data)
        with autoraise = autoraise;
    }

    // ---------- internal functions ----------
    // eci is optional
    get_my_esl = function(eci){
      use_eci = eci || meta:eci();
      eid = math:random("9999999")
      "https://#{meta:host}/sky/event/#{use_eci}/eid/"
    }

  }

  rule carvoyant_init_subscription {
    select when carvoyant init
    pre {
      sub_type = event:attr("subscription_type");
      params = {"minimumTime": event:attr("minimumTime") || 60,
                "postUrl": get_my_eci()
	       }
    }
    if valid_subscription_type(sub_type) then 
        carvoyant_add_subscription(sub_type, params) with
    	  autoraise = sub_type;
    notfired {
      error warn "Invalid Carvoyant event subscription type: #{sub_type}"
    }
  }

  rule subscription_ok {
    select when http post status_code #(2\d\d)# setting (status)
    pre {
      sub = event:attr('content').decode().pick("$.subscription");
      new_subs = ent:subscriptions.put();
    }
    noop()
    always {
      set ent:subscriptions new_subs
    }
  }

  rule subscription_fail {
    select when http post status_code #([45]\d\d)# setting (status)
    noop()
    fired {
      error warn "Carvoyant HTTP Error (#{status}): ${event:attr('status_line')}. Autoraise label: #{event:attr('label')}."
    }
  }


}