// not checked into Git
Fuse.defaults.logging = true;

// login and initialize
CloudOS.login(username, password, function(){
    Fuse.init(show_res);
}, show_res);
