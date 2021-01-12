# WebServerFor

A very tiny local web server.

This has precisely the following features of interest:

* Serves the provided file as `/` and other files relative to it  
  (without requiring it to be named `index.html`)
* Has minimal caching  
  (accessed items are stored in memory until their `mtime` changes)
* Written for use with `live.js` userscript variation (included).  
  The server will also "wiggle" reported file sizes in HEAD when the content changes without file size change (such as tweaking colors in CSS).

## How to use

```
webserverfor path/some.html
```
or
```
webserverfor path/some.html --port 2000
```

## Building
```
haxe build.hxml
```