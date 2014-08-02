ruleset fuse_fleet_oauth {
    meta {
        name "Fuse Fleet OAuth"
        description <<
Ruleset for fleet OAuth stuff
        >>

        use module a169x625 alias CloudOS
        use module a169x676 alias pds
	use module b16x19 alias common

	use module b16x10 alias fuse_keys

	errors to b16x13
	
	sharing on



	provides clientAccessToken,  refreshTokenForAccessToken, showTokens, forgetTokens, forgetAllTokens, // don't provide after debug
             isAuthorized, redirectUri, carvoyantOauthUrl, codeForAccessToken, getTokens, fixToken

    }

    global {
    
      // duplicated here and in fuse_carvoyant.krl
      api_hostname = "api.carvoyant.com";
      apiHostname = function() {api_hostname};
      oauth_url = "https://"+api_hostname+"/oauth/token";

      // appears in both this ruleset and fuse_carvoyant
      namespace = function() {
        "fuse:carvoyant";
      };

      // ---------- authorization ----------

   
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

      redirectUri = function() {
        "https://" + meta:host() + "/sky/event/" + keys:anonymous_pico("eci")  + "/" + math:random(9999) +  "/oauth/new_oauth_code";
      }



      // this function creates a carvoyant OAuth URL that leads the user to a login screen. 
      // the redirect URL gets picked up by the anonymous pico's CloudOS handleOauthCode rule 
      carvoyantOauthUrl = function(hostsite) {
    
        redirect_uri = redirectUri();
        accessing_eci = meta:eci();

        params = {"client_id" : keys:carvoyant_client("client_id"),	
                  "redirect_uri" : redirect_uri,
  		  "response_type" : "code",
  		  "state": [meta:rid(), accessing_eci, hostsite ].join(",")
		 };

        query_string = params.map(function(k,v){k+"="+v}).values().join("&").klog(">>>>> query string >>>>>>");
        {"url": "https://auth.carvoyant.com/OAuth/authorize?" + query_string}
      }



      // CloudOS:handleOauthCode rule redirects to this function based on state param created in carvoyantOathUrl()
      codeForAccessToken = function(code, redirect_uri, hostsite) {
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
        results = (raw_result{"status_code"} eq "200") => normalizeAccountInfo(raw_result{"content"}.decode())
                                                        | raw_result.decode();

        // hardcoded URL!!
        url = hostsite + "?" +
                results.map(function(k,v){k + "=" + v}).values().join("&").klog(">>>>> url >>>>>");
        
        page = <<
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title></title>
  <META HTTP-EQUIV="Refresh" CONTENT="0;url=#{url}">
  <meta name="robots" content="noindex"/>
  <link rel="canonical" href="#{url}"/>
</head>
<body>
<p>
You are being redirected to <a href="#{url}">#{url}</a>
</p>

</body>
</html>
        >>;

        page
      };

    fixToken = function() {
      account_info = ent:account_info || {};
      try_refresh = not account_info{"refresh_token"}.isnull();
      new_tokens = try_refresh => refreshTokenForAccessToken().klog(">>>>> refreshing for carvoyant_get() >>> ")
                                | {};
      new_tokens
    };


      refreshTokenForAccessToken = function() {
        account_info = ent:account_info || {};
        header = 
            {"credentials": {
               "username": keys:carvoyant_client("client_id"),
               "password": keys:carvoyant_client("client_secret"),
	       "realm": apiHostname(),
	       "netloc": apiHostname() + ":443"
               },
             "params" : {"grant_type": "refresh_token",
	                 "refresh_token": account_info{"refresh_token"}
	                }
            };
        raw_result = http:post(oauth_url, header);
        (raw_result{"status_code"} eq "200") => normalizeAccountInfo(raw_result{"content"}.decode())
                                              | raw_result.decode()
      };

      normalizeAccountInfo = function(account_info) {

        // raise an event to broadcast new config
//        response = cloudos:sendEvent(meta:eci(), "fuse", "config_outdated", account_info);
	
        // add the timestamp and then store the info in an entity var (ugh; evil)
        account_info.put(["timestamp"], time:now()).pset(ent:account_info);
      }

      forgetTokens = function(){
        "".pset(ent:account_info{["access_token"]})
      };

      forgetAllTokens = function(){
        {}.pset(ent:account_info)
      };

      showTokens = function() {
        ent:account_info
      };

      // only give tokens to pico who identify themselves and we confirm they came in on the channel
      //   that they are subscribed on
      //   (i.e. to get tokens, you need to know ID and channel for the pico making request)
      getTokensForVehicle = function(id) {
        vehicle_ecis = CloudOS:subscriptionList(common:namespace(),"Vehicle").klog(">>>> some vehicle ECIs >>>>");
	vehicle_ecis_by_id = vehicle_ecis.collect(function(x){x{"channelName"}}).map(function(k,v){v.head()});
	caller = vehicle_ecis_by_id{id}.klog(">>>> this caller >>>>>") || {};
	incoming_eci = meta:eci().klog(">>>> incoming ECI >>>>>");
	caller{"backChannel"} eq incoming_eci => ent:account_info
	                                        | {}
      };

      getTokens = function(id) {
        // this is ad hoc authentication
        caller = meta:callingRID().klog(">>>> calling rid >>>>>");
	allowed = common:allowedRids().klog(">>>> allowed rids >>>>");
	account_info = ent:account_info.klog(">>>> seeing account_info >>>>") || {};
        allowed.any(function(x){x eq caller}) => account_info
	                               	      | getTokensForVehicle(id)
      };	
	

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
      client_access_token = carvoyant_oauth:clientAccessToken();
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

      url = (api_url+"/account/").klog(">>>>>> account creation url <<<<<<<<<<");

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
      tokens = carvoyant_oauth:codeForAccessToken(code, carvoyant_oauth:redirectUri()); // mutates ent:account_info
    }

    {
      send_directive("Exchanged account code for account tokens") with tokens = tokens
    }
    fired {
      raise carvoyant event new_tokens_available with tokens = getTokens() //ent:account_info
    }
  }

  rule error_carvoyant_acct_creation {
    select when http post status_code  re#[45]\d\d#  label "account_init"

    always {
      log ">>>>> carvoyant account creation failed " + event:attrs().encode();
    }

  }


  // ---------- token stuff ----------
  rule update_token {
    select when carvoyant access_token_expired

    pre {
      tokens = carvoyant_oauth:refreshTokenForAccessToken(); // mutates
    }
    if( tokens{"error"}.isnull() ) then 
    {
      send_directive("Used refresh token to get new account token");
      // send to each vehicle...
    }
    fired {
      raise carvoyant event new_tokens_available with tokens = getTokens() // ent:account_info
    } else {
      log(">>>>>>> couldn't use refresh token to get new access token <<<<<<<<");
    }
    
  }
  
  // used by both fleet and vehicle to store tokens
  rule store_tokens {
    select when carvoyant new_tokens_available
    pre {
      tokens = event:attr("tokens").decode();
      new_tokens = ( not tokens.isnull() ) => carvoyant_oauth:normalizeAccountInfo(tokens)
                                            | {};
    }
    if( not tokens.isnull() ) then 
    {
      send_directive("Storing new tokens");
      // send to each vehicle...
    }
    fired {
      log(">>>>>>> new tokens! w00t! >>>>>>>>");
    } else {  
      log(">>>>>>> tokens empty <<<<<<<<");
    }
  }

  // this needs to be in fleet carvoyant ruleset, not vehicle
  // inactive cause vehicles now ask for tokens
  rule send_vehicle_new_config is inactive {
    select when fuse config_outdated
    foreach common:vehicleChannels().pick("$..channel") setting (vehicle_channel)
    pre {
      account_info = getTokens();
    }
    {
      send_directive("Sending Carvoyant config to " + vehicle_channel) with 
        tokens = account_info; 
      event:send({"cid": vehicle_channel}, "carvoyant", "new_tokens_available") with
        attrs = {"tokens": account_info.encode()
         };
    }
  }




}