// not checked into Git
Fuse.defaults.logging = true;
var username = "pjw+fuse_03@kynetx.com";
var password = "fizzbazz"; 

// login and initialize
CloudOS.login(username, password, function(){
    Fuse.init(show_res);
}, show_res);
