// cp this template to CloudOS-config.js

// This is the developer key or token. You should have gotten this when you registered your app with KDK
// KDK calls this the token of app ECI
CloudOS.appKey = "<app key goes here>";

// anon ECI (probably no need to change this)
CloudOS.anonECI = "85255500-0b65-0130-243c-00163ebcdddd";

// you can likely leave these alone
CloudOS.host = "cs.kobj.net";
CloudOS.login_server = "login.kynetx.com";

// this must return a registered redirect URL
CloudOS.callbackURL = window.location.href.split('#')[0];
