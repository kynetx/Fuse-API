ruleset fuse_carvoyant {
  meta {
    name "Fuse Carvoyant Ruleset"
    author "Phil Windley"
    description <<
Provides rules for handling Carvoyant events
>>
  
  }

  global {

    hostname = "dash.carvoyant.com";
    carvoyant_config_key = "fuse:carvoyant";

    // ---------- general carvoyant API access functions ----------
    carvoyant_api_url = function(vehicle_id) {
      "https://#{hostname}/api/vehicle/"+ vehicle_id
    };

    carvoyant_headers = function(config_data, params) {
      {"credentials": {
          "username": config_data{"apiKey"},
          "password": config_data{"secToken"},
          "realm": "Carvoyant API",
          "netloc": "#{hostname}:443"
          },
       "params" : params || {}
      }
    };

    carvoyant_get = function(url, config_data, params) {
      http:get(url, carvoyant_headers(config_data, params))
    };

    carvoyant_post = defaction(url, config_data, params) {
      http:post(url, carvoyant_headers(config_data, params))
    };

    carvoyant_put = defaction(url, config_data, params) {
      http:put(url, carvoyant_headers(config_data, params))
    };

    carvoyant_delete = defaction(url, config_data) {
      http:delete(url, carvoyant_headers(config_data))
    };

    // ---------- subscriptions ----------
    carvoyant_subscription_url = function(vehicle_id, subscription_type, subscription_id) {
       base_url = covyant_api_url(vehicle_id) + "/eventSubscription/" + subsciption_type;
       subscription_id.isnull() => base_url 
	                         | base_url + "/" + subscription_id
    };

    // subscription_id is optional, if left off, retrieves all subscriptions of given type
    cavoyant_get_subscription = defaction(subscription_type, params, subscription_id) {
       carvoyant_config_data = pds:get_items(carvoyant_config_key);
       carvoyant_post(carvoyant_subscription_url(carvoyant_config_data{"deviceID"}, subscription_type, subscription_id),
                      carvoyant_config_data,
		      parmams)
    }


    cavoyant_add_subscription = defaction(subscription_type, params) {
       carvoyant_config_data = pds:get_items(carvoyant_config_key);
       carvoyant_post(carvoyant_subscription_url(carvoyant_config_data{"deviceID"}, subscription_type),
                      carvoyant_config_data,
		      parmams)
    }

    cavoyant_del_subscription = defaction(subscription_type, subscription_id) {
       carvoyant_config_data = pds:get_items(carvoyant_config_key);
       carvoyant_delete(carvoyant_subscription_url(carvoyant_config_data{"deviceID"}, subscription_type, subscription_id),
                        carvoyant_config_data)
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