; (function()
{
    window.CloudOS = {};

    // ------------------------------------------------------------------------

    CloudOS.defaultECI = "none";
    CloudOS.access_token = "none";

    var mkEci = function(cid) {
	var res = cid || CloudOS.defaultECI;
        if (res === "none") {
	    throw "No CloudOS event channel identifier (ECI) defined";
        }
	return res;
    };

    var mkEsl = function(parts) {
        if (CloudOS.host === "none") {
            throw "No CloudOS host defined";
        }
	parts.unshift(CloudOS.host);
	var res = 'https://'+ parts.join("/");
	return res;
    };

    // ------------------------------------------------------------------------
    // Raise Sky Event
    CloudOS.raiseEvent = function(eventDomain, eventType, eventAttributes, eventParameters, postFunction, options)
    {
	try {

	    options = options || {};

	    var eci = mkEci(options.eci);
            var eid = Math.floor(Math.random() * 9999999);
            var esl = mkEsl(['sky/event',
			     eci,
			     eid,
			     eventDomain,
			     eventType
			    ]);

            if (typeof eventParameters !== "undefined" &&
		eventParameters !== null &&
		eventParameters !== ""
	       ) {
		   console.log("Attaching event parameters ", eventParameters);
		   var param_string = $.param(eventParameters);
		   if (param_string.length > 0) {
                       esl = esl + "?" + param_string;
		   }
               }

            console.log("CloudOS.raise ESL: ", esl);
            console.log("event attributes: ", eventAttributes);

            return $.ajax({
		type: 'POST',
		url: esl,
		data: $.param(eventAttributes),
		dataType: 'json',
		headers: { 'Kobj-Session': eci }, // not sure needed since eci in URL
		success: postFunction,
		error: options.errorFunc || function(res) { console.error(res) }
            });
	} catch(error) {
	    console.error("[raise]", error);
	    return null;
	}
    };

    CloudOS.skyCloud = function(module, func_name, parameters, getSuccess, options)
    {
	try {

	    var retries = 2;
	    
	     console.log("Options ", options);

	    options = options || {};

	    console.log("Options ", options);

            if (typeof options.repeats !== "undefined") {
		console.warn("This is a repeated request: ", options.repeats);
		if (options.repeats > retries) {
                    throw "terminating repeating request due to consistent failure.";
		}
            }

	    var eci = mkEci(options.eci);

            var esl = mkEsl(['sky/cloud',
			     module,
			     func_name
			    ]);

            $.extend(parameters, { "_eci": eci });

            console.log("Attaching event parameters ", parameters);
            esl = esl + "?" + $.param(parameters);

            var process_error = function(res)
            {
		console.error("skyCloud Server Error with esl ", esl, res);
		if (typeof options.errorFunc === "function") {
                    options.errorFunc(res);
		}
            };

            var process_result = function(res)
            {
		console.log("Seeing res ", res, " for ", esl);
		var sky_cloud_error = typeof res === 'Object' && typeof res.skyCloudError !== 'undefined';
		if (! sky_cloud_error ) {
                    getSuccess(res);
		} else {
                    console.error("skyCloud Error (", res.skyCloudError, "): ", res.skyCloudErrorMsg);
                    if (!!res.httpStatus && 
			!!res.httpStatus.code && 
			(parseInt(res.httpStatus.code) === 400 || parseInt(res.httpStatus.code) === 500)) 
		    {
			console.error("The request failed due to an ECI error. Going to repeat the request.");
			var repeat_num = (typeof options.repeats !== "undefined") ? ++options.repeats : 0;
			options.repeats = repeat_num;
			// I don't think this will support promises; not sure how to fix
			CloudOS.skyCloud(module, func_name, parameters, getSuccess, options);
                    }
		}
            };

            console.log("sky cloud call to ", module+':'+func_name, " on ", esl, " with token ", eci);

            return $.ajax({
		type: 'GET',
		url: esl,
		dataType: 'json',
		// try this as an explicit argument
		//		headers: {'Kobj-Session' : eci},
		success: process_result
		// error: process_error
            });
	} catch(error) {
	    console.error("[skyCloud]", error);
	    if (typeof options.errorFunc === "function") {
		options.errorFunc();
	    } 
	    return null;
	}
    };


    // ------------------------------------------------------------------------
    CloudOS.createChannel = function(postFunction)
    {
        return CloudOS.raiseEvent('cloudos', 'api_Create_Channel', {}, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.destroyChannel = function(myToken, postFunction)
    {
        return CloudOS.raiseEvent('cloudos', 'api_Destroy_Channel',
			{ "token": myToken }, {}, postFunction);
    };

    // ========================================================================
    // Profile Management

    CloudOS.getMyProfile = function(getSuccess)
    {
        return CloudOS.skyCloud("a169x676", "get_all_me", {}, function(res) {
	    clean(res);
	    if(typeof getSuccess !== "undefined"){
		getSuccess(res);
	    }
	});
    };

    CloudOS.updateMyProfile = function(eventAttributes, postFunction)
    {
        var eventParameters = { "element": "profileUpdate.post" };
        return CloudOS.raiseEvent('web', 'submit', eventAttributes, eventParameters, postFunction);
    };

    CloudOS.getFriendProfile = function(friendToken, getSuccess)
    {
        var parameters = { "myToken": friendToken };
        return CloudOS.skyCloud("a169x727", "getFriendProfile", parameters, getSuccess);
    };

    // ========================================================================
    // PDS Management

    // ------------------------------------------------------------------------
    CloudOS.PDSAdd = function(namespace, pdsKey, pdsValue, postFunction)
    {
        var eventAttributes = {
            "namespace": namespace,
            "pdsKey": pdsKey,
            "pdsValue": JSON.stringify(pdsValue)
        };

        return CloudOS.raiseEvent('cloudos', 'api_pds_add', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.PDSDelete = function(namespace, pdsKey, postFunction)
    {
        var eventAttributes = {
            "namespace": namespace,
            "pdsKey": pdsKey
        };

        return CloudOS.raiseEvent('cloudos', 'api_pds_delete', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.PDSUpdate = function()
    {
    };

    // ------------------------------------------------------------------------
    CloudOS.PDSList = function(namespace, getSuccess)
    {
        var callParmeters = { "namespace": namespace };
        return CloudOS.skyCloud("pds", "get_items", callParmeters, getSuccess);
    };

    // ------------------------------------------------------------------------
    CloudOS.sendEmail = function(ename, email, subject, body, postFunction)
    {
        var eventAttributes = {
            "ename": ename,
            "email": email,
            "subject": subject,
            "body": body
        };
        return CloudOS.raiseEvent('cloudos', 'api_send_email', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.sendNotification = function(application, subject, body, priority, token, postFunction)
    {
        var eventAttributes = {
            "application": application,
            "subject": subject,
            "body": body,
            "priority": priority,
            "token": token
        };
        return CloudOS.raiseEvent('cloudos', 'api_send_notification', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.subscriptionList = function(callParmeters, getSuccess)
    {
        return CloudOS.skyCloud("cloudos", "subscriptionList", callParmeters, getSuccess);
    };


    // ========================================================================
    // Login functions
    // ========================================================================
    CloudOS.login = function(username, password, success, failure) {


	var parameters = {"email": username, "pass": password};

        if (typeof CloudOS.anonECI === "undefined") {
	    console.error("CloudOS.anonECI undefined. Configure CloudOS.js in CloudOS-config.js; failing...");
	    return null;
        }

	return CloudOS.skyCloud("cloudos",
				"cloudAuth", 
				parameters, 
				function(res){
				    // patch this up since it's not OAUTH
				    var tokens = {"access_token": "none",
						  "OAUTH_ECI": res.token
						 };
				    CloudOS.saveSession(tokens); success(tokens);}, 
				{eci: CloudOS.anonECI,
				 errorFunc: failure
				}
			       );


    };



    // ========================================================================
    // OAuth functions
    // ========================================================================

    // ------------------------------------------------------------------------
    CloudOS.getOAuthURL = function(fragment)
    {
        if (typeof CloudOS.login_server === "undefined") {
            CloudOS.login_server = CloudOS.host;
        }


        var client_state = Math.floor(Math.random() * 9999999);
        var current_client_state = window.localStorage.getItem("CloudOS_CLIENT_STATE");
        if (!current_client_state) {
            window.localStorage.setItem("CloudOS_CLIENT_STATE", client_state.toString());
        }
        var url = 'https://' + CloudOS.login_server +
			'/oauth/authorize?response_type=code' +
			'&redirect_uri=' + encodeURIComponent(CloudOS.callbackURL + (fragment || "")) +
			'&client_id=' + CloudOS.appKey +
			'&state=' + client_state;

        return (url)
    };

    // ------------------------------------------------------------------------
    CloudOS.getOAuthAccessToken = function(code, callback)
    {
        var returned_state = parseInt(getQueryVariable("state"));
        var expected_state = parseInt(window.localStorage.getItem("CloudOS_CLIENT_STATE"));
        if (returned_state !== expected_state) {
            console.warn("OAuth Security Warning. Client state's do not match. (Expected %d but got %d)", CloudOS.client_state, returned_state);
        }
        console.log("getting access token with code: ", code);
        if (typeof (callback) !== 'function') {
            callback = function() { };
        }
        var url = 'https://' + CloudOS.login_server + '/oauth/access_token';
        var data = {
            "grant_type": "authorization_code",
            "redirect_uri": CloudOS.callbackURL,
            "client_id": CloudOS.appKey,
            "code": code
        };

        return $.ajax({
            type: 'POST',
            url: url,
            data: data,
            dataType: 'json',
            success: function(json)
            {
                console.log("Recieved following authorization object from access token request: ", json);
                if (!json.OAUTH_ECI) {
                    console.error("Recieved invalid OAUTH_ECI. Not saving session.");
                    callback(json);
                    return;
                };
                CloudOS.saveSession(json);
                window.localStorage.removeItem("CloudOS_CLIENT_STATE");
                callback(json);
            },
            error: function(json)
            {
                console.log("Failed to retrieve access token " + json);
            }
        });
    };

    // ========================================================================
    // Session Management

    // ------------------------------------------------------------------------
    CloudOS.retrieveSession = function()
    {
        var SessionCookie = kookie_retrieve();

        console.log("Retrieving session ", SessionCookie);
        if (SessionCookie != "undefined") {
            CloudOS.defaultECI = SessionCookie;
        } else {
            CloudOS.defaultECI = "none";
        }
	return CloudOS.defaultECI;
    };

    // ------------------------------------------------------------------------
    CloudOS.saveSession = function(token_json)
    {
	var Session_ECI = token_json.OAUTH_ECI;
	var access_token = token_json.access_token;
        console.log("Saving session for ", Session_ECI);
        CloudOS.defaultECI = Session_ECI;
	CloudOS.access_token = access_token;
        kookie_create(Session_ECI);
    };
    // ------------------------------------------------------------------------
    CloudOS.removeSession = function(hard_reset)
    {
        console.log("Removing session ", CloudOS.defaultECI);
        if (hard_reset) {
            var cache_breaker = Math.floor(Math.random() * 9999999);
            var reset_url = 'https://' + CloudOS.login_server + "/login/logout?" + cache_breaker;
            $.ajax({
                type: 'POST',
                url: reset_url,
                headers: { 'Kobj-Session': CloudOS.defaultECI },
                success: function(json)
                {
                    console.log("Hard reset on " + CloudOS.login_server + " complete");
                }
            });
        }
        CloudOS.defaultECI = "none";
        kookie_delete();
    };

    // ------------------------------------------------------------------------
    CloudOS.authenticatedSession = function()
    {
        var authd = CloudOS.defaultECI != "none";
        if (authd) {
            console.log("Authenicated session");
        } else {
            console.log("No authenicated session");
        }
        return (authd);
    };

    // exchange OAuth code for token
    // updated this to not need a query to be passed as it wasnt used in the first place.
    CloudOS.retrieveOAuthCode = function()
    {
        var code = getQueryVariable("code");
        return (code) ? code : "NO_OAUTH_CODE";
    };

    function getQueryVariable(variable)
    {
        var query = window.location.search.substring(1);
        var vars = query.split('&');
        for (var i = 0; i < vars.length; i++) {
            var pair = vars[i].split('=');
            if (decodeURIComponent(pair[0]) == variable) {
                return decodeURIComponent(pair[1]);
            }
        }
        console.log('Query variable %s not found', variable);
        return false;
    };

    function clean(obj) {
	delete obj._type;
	delete obj._domain;
	delete obj._async;
	
    };

    var SkyTokenName = '__SkySessionToken';
    var SkyTokenExpire = 7;

    // --------------------------------------------
    function kookie_create(SkySessionToken)
    {
        if (SkyTokenExpire) {
            // var date = new Date();
            // date.setTime(date.getTime() + (SkyTokenExpire * 24 * 60 * 60 * 1000));
            // var expires = "; expires=" + date.toGMTString();
            var expires = "";
        }
        else var expires = "";
        var kookie = SkyTokenName + "=" + SkySessionToken + expires + "; path=/";
        document.cookie = kookie;
        // console.debug('(create): ', kookie);
    }

    // --------------------------------------------
    function kookie_delete()
    {
        var kookie = SkyTokenName + "=foo; expires=Thu, 01-Jan-1970 00:00:01 GMT; path=/";
        document.cookie = kookie;
        // console.debug('(destroy): ', kookie);
    }

    // --------------------------------------------
    function kookie_retrieve()
    {
        var TokenValue = 'undefined';
        var TokenName = '__SkySessionToken';
        var allKookies = document.cookie.split('; ');
        for (var i = 0; i < allKookies.length; i++) {
            var kookiePair = allKookies[i].split('=');
            // console.debug("Kookie Name: ", kookiePair[0]);
            // console.debug("Token  Name: ", TokenName);
            if (kookiePair[0] == TokenName) {
                TokenValue = kookiePair[1];
            };
        }
        // console.debug("(retrieve) TokenValue: ", TokenValue);
        return TokenValue;
    }

})();
