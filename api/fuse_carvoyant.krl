ruleset fuse_carvoyant {
  meta {
    name "Fuse Carvoyant Ruleset"
    author "Phil Windley"
    description <<
Provides rules for handling Carvoyant events
>>
  
  }

  global {

    // config data contains
    //   deviceID - Carvoyant device ID
    //   apiKey - API Key in http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism
    //   secToken - Access Token in http://confluence.carvoyant.com/display/PUBDEV/Authentication+Mechanism 

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
      http:post(url, carvoyant_headers(config_data, params))
    };

    carvoyant_put = defaction(url, params, config_data) {
      http:put(url, carvoyant_headers(config_data, params))
    };

    carvoyant_delete = defaction(url, config_data) {
      http:delete(url, carvoyant_headers(config_data))
    };

    // ---------- subscriptions ----------
    carvoyant_subscription_url = function(subscription_type, config_data, subscription_id) {
       base_url = config_data{"base_url"} + "/eventSubscription/" + subsciption_type;
       subscription_id.isnull() => base_url 
	                         | base_url + "/" + subscription_id
    };

    // subscription functions
    // subscription_id is optional, if left off, retrieves all subscriptions of given type
    cavoyant_get_subscription = function(subscription_type, subscription_id) {
       config_data = get_config();
       carvoyant_get(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
		     config_data)
    };


    // subscription actions
    cavoyant_add_subscription = defaction(subscription_type, params) {
       config_data = get_config();
       carvoyant_post(carvoyant_subscription_url(subscription_type, config_data),
                      config_data,
		      params)
    };

    cavoyant_del_subscription = defaction(subscription_type, subscription_id) {
       config_data = get_config();
       carvoyant_delete(carvoyant_subscription_url(subscription_type, config_data, subscription_id),
                        config_data)
    }

  }

  rule carvoyant_init is inactive {
    select when carvoyant init
    pre {
      params = {"minimumTime": 20,
                "postUrl": "<valid ESL here>"
	       }
    }
    carvoyant_add_subscription("lowBattery", params) setting(batt_response);
    always {
      set ent:low_battery_subscription_id  batt_response.decode().pick("$..id");
    }
  }

}