; (function()
{
    window.CloudOS = {};

    // ------------------------------------------------------------------------
    // Personal Cloud Hostname
    // Also in config now.
    // CloudOS.host = "cs.kobj.net";

    // these should be in config now..
    // CloudOS.appKey = "C665EA88-3613-11E3-862C-61A7D61CF0AC";

    // CloudOS.callbackURL = "http://hbdc.kynetx.com/";

    CloudOS.sessionToken = "none";

    CloudOS.deviceToken = "none";

    // ------------------------------------------------------------------------
    // Raise Sky Event
    CloudOS.raiseEvent = function(eventDomain, eventType, eventAttributes, eventParameters, postFunction)
    {


        if (CloudOS.host === "none") {
            console.error("No CloudOS host defined");
            return;
        }

        if (CloudOS.sessionToken === "none") {
            console.error("No CloudOS session token defined");
            return;
        }



        var eid = Math.floor(Math.random() * 9999999);
        var esl = 'https://' + CloudOS.host + '/sky/event/' +
            CloudOS.sessionToken + '/' + eid + '/' +
	     eventDomain + '/' + eventType;

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

        $.ajax({
            type: 'POST',
            url: esl,
            data: $.param(eventAttributes),
            dataType: 'json',
            headers: { 'Kobj-Session': CloudOS.sessionToken }, // not sure needed since eci in URL
            success: postFunction,
            error: function(res) { console.error(res) }
        });
    };

    // I don't know what these device functions are. Does anyone else? 
    CloudOS.raiseEventDevice = function(eventDomain, eventType, eventAttributes, eventParameters, postFunction)
    {
        var eid = Math.floor(Math.random() * 9999999);
        var esl = 'https://' + CloudOS.host + '/sky/event/' +
            CloudOS.deviceToken + '/' + eid + '/' +
            eventDomain + '/' + eventType +
            "?" + eventParameters;

        $.ajax({
            type: 'POST',
            url: esl,
            data: eventAttributes,
            dataType: 'json',
            headers: { 'Kobj-Session': CloudOS.deviceToken },
            success: postFunction,
        });
    };

    CloudOS.skyCloud = function(Module, FuncName, parameters, getSuccess, getError, repeats)
    {

	var retries = 2;

        if (typeof repeats !== "undefined") {
            console.warn("This is a repeated request: ", repeats);
            if (repeats > retries) {
                console.error("terminating repeating request due to consistent failure.");
		if (typeof getError === "function") {
                    getError();
		    return;
		} else {
		    // no error function defined...
		    // [PJW] I don't like having things that depend on a browser window mixed in this code...
                    alert("Something went wrong! If the problem persists, contact the kynetx development team.");
                    window.location.search = "";
		}
                return;
            }
        }

        if (CloudOS.host === "none") {
            console.error("No CloudOS host defined");
            return;
        }

        if (CloudOS.sessionToken === "none") {
            console.error("No CloudOS session token defined");
            return;
        }

        var esl = 'https://' +
                   CloudOS.host +
                   '/sky/cloud/' +
	               Module + '/' + FuncName;

        $.extend(parameters, { "_eci": CloudOS.sessionToken });

        console.log("Attaching event parameters ", parameters);
        esl = esl + "?" + $.param(parameters);

        var process_error = function(res)
        {
            console.error("skyCloud Server Error with esl ", esl, res);
            if (typeof getError === "function") {
                getError(res);
            }
        };

        var process_result = function(res)
        {
            //        console.log("Seeing res ", res, " for ", esl);
            if (typeof res.skyCloudError === 'undefined') {
                getSuccess(res);
            } else {
                console.error("skyCloud Error (", res.skyCloudError, "): ", res.skyCloudErrorMsg);
                if (!!res.httpStatus && !!res.httpStatus.code && (parseInt(res.httpStatus.code) === 400 || parseInt(res.httpStatus.code) === 500)) {
                    console.error("The request failed due to an ECI error. Going to repeat the request.");
                    var repeat_num = (typeof repeats !== "undefined") ? ++repeats : 0;
                    CloudOS.skyCloud(Module, FuncName, parameters, getSuccess, getError, repeat_num);
                }
            }
        };

        console.log("sky cloud call to ", FuncName, " on ", esl, " with token ", CloudOS.sessionToken);

        $.ajax({
            type: 'GET',
            url: esl,
            dataType: 'json',
            // try this as an explicit argument
            //		headers: {'Kobj-Session' : CloudOS.sessionToken},
            success: process_result
            // error: process_error
        });
    };

    CloudOS.skyCloudDevice = function(Module, FuncName, parameters, getSuccess)
    {
        var esl = 'https://' + CloudOS.host + '/sky/cloud/' +
					Module + '/' + FuncName + '?' + parameters;

        $.ajax({
            type: 'GET',
            url: esl,
            dataType: 'json',
            headers: { 'Kobj-Session': CloudOS.deviceToken },
            success: getSuccess
        });
    };


    // ------------------------------------------------------------------------
    CloudOS.createChannel = function(postFunction)
    {
        CloudOS.raiseEvent('cloudos', 'api_Create_Channel', {}, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.destroyChannel = function(myToken, postFunction)
    {
        CloudOS.raiseEvent('cloudos', 'api_Destroy_Channel',
			{ "token": myToken }, {}, postFunction);
    };

    // ========================================================================
    // Profile Management

    CloudOS.getMyProfile = function(getSuccess)
    {
        CloudOS.skyCloud("a169x676", "get_all_me", {}, getSuccess);
    };

    CloudOS.updateMyProfile = function(eventAttributes, postFunction)
    {
        var eventParameters = { "element": "profileUpdate.post" };
        CloudOS.raiseEvent('web', 'submit', eventAttributes, eventParameters, postFunction);
    };

    CloudOS.getFriendProfile = function(friendToken, getSuccess)
    {
        var parameters = { "myToken": friendToken };
        CloudOS.skyCloud("a169x727", "getFriendProfile", parameters, getSuccess);
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

        CloudOS.raiseEvent('cloudos', 'api_pds_add', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.PDSDelete = function(namespace, pdsKey, postFunction)
    {
        var eventAttributes = {
            "namespace": namespace,
            "pdsKey": pdsKey
        };

        CloudOS.raiseEvent('cloudos', 'api_pds_delete', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.PDSUpdate = function()
    {
    };

    // ------------------------------------------------------------------------
    CloudOS.PDSList = function(namespace, getSuccess)
    {
        var callParmeters = { "namespace": namespace };
        CloudOS.skyCloud("pds", "get_items", callParmeters, getSuccess);
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
        CloudOS.raiseEvent('cloudos', 'api_send_email', eventAttributes, {}, postFunction);
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
        CloudOS.raiseEvent('cloudos', 'api_send_notification', eventAttributes, {}, postFunction);
    };

    // ========================================================================
    // Subscription Management

    // ------------------------------------------------------------------------
    CloudOS.subscribe = function(namespace, name, relationship, token, subAttributes, postFunction)
    {
        var eventAttributes = {
            "namespace": namespace,
            "channelName": name,
            "relationship": relationship,
            "targetChannel": token,
            "subAttrs": subAttributes
        };
        CloudOS.raiseEvent('cloudos', 'api_subscribe', eventAttributes, {}, postFunction);
    };

    // ------------------------------------------------------------------------
    CloudOS.subscriptionList = function(callParmeters, getSuccess)
    {
        CloudOS.skyCloud("cloudos", "subscriptionList", callParmeters, getSuccess);
    };

    CloudOS.getFriendsList = function(getSuccess)
    {
        CloudOS.skyCloud("a169x727", "getFriendsList", {}, getSuccess);
    };

    // ========================================================================
    // OAuth functions

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

        $.ajax({
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
                CloudOS.saveSession(json.OAUTH_ECI);
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
            CloudOS.sessionToken = SessionCookie;
        } else {
            CloudOS.sessionToken = "none";
        }
    };

    // ------------------------------------------------------------------------
    CloudOS.saveSession = function(Session_ECI)
    {
        console.log("Saving session for ", Session_ECI);
        CloudOS.sessionToken = Session_ECI;
        kookie_create(Session_ECI);
    };

    CloudOS.saveDeviceToken = function(deviceChannel)
    {
        CloudOS.deviceToken = deviceChannel;
    };

    // ------------------------------------------------------------------------
    CloudOS.removeSession = function(hard_reset)
    {
        console.log("Removing session ", CloudOS.sessionToken);
        if (hard_reset) {
            var cache_breaker = Math.floor(Math.random() * 9999999);
            var reset_url = 'https://' + CloudOS.login_server + "/login/logout?" + cache_breaker;
            $.ajax({
                type: 'POST',
                url: reset_url,
                headers: { 'Kobj-Session': CloudOS.sessionToken },
                success: function(json)
                {
                    console.log("Hard reset on " + CloudOS.login_server + " complete");
                }
            });
        }
        CloudOS.sessionToken = "none";
        kookie_delete();
    };

    // ------------------------------------------------------------------------
    CloudOS.authenticatedSession = function()
    {
        var authd = CloudOS.sessionToken != "none";
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
