
function show_res(){
    if (console && console.log) {
	[].unshift.call(arguments, "Showing:"); // arguments is Array-like, it's not an Array 
        console.log.apply(console, arguments);
    } 
}
