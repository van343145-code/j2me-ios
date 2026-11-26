  (function() {
    'use strict';

    // Callback registries for evalNative commands
    window.__j2meNetworkCallbacks = Object.create(null);
    window.__j2meSocketCallbacks = {};

    // Unique ID counter for request tracking
    var __j2meRequestId = 0;

    /**
     * evalNative - bridge between J2meJS engine and native network APIs
     * Called by main-all.js when J2ME code makes HTTP or socket requests
     *
     * @param {string} command - "request" | "connectSocket" | "onSocket" | "invokeSocket"
     * @param {object} data - command parameters
     * @param {function} [callback] - optional callback for async responses
     */
    window.evalNative = function(command, data, callback) {
      switch (command) {
        case "request": {
          // HTTP requests can complete out of order. Give each callback its own ID.
          var requestId = "request_" + __j2meRequestId++;
          if (typeof callback === "function") {
            window.__j2meNetworkCallbacks[requestId] = callback;
          }
          window.webkit.messageHandlers.j2me.postMessage({
            type: "evalNative",
            command: "request",
            data: data,
            requestId: requestId,
            hasCallback: typeof callback === "function"
          });
          break;
        }

        case "connectSocket": {
          // TCP socket connect - send to Swift with a unique socket ID
          var socketId = "socket_" + __j2meRequestId++;
          // Include socketId in the data sent to Swift
          var sendData = Object.assign({}, data, { __socketId: socketId });
          window.webkit.messageHandlers.j2me.postMessage({
            type: "evalNative",
            command: "connectSocket",
            data: sendData,
            hasCallback: typeof callback === "function"
          });
          // Store callback keyed by socketId
          if (typeof callback === "function") {
            window.__j2meSocketCallbacks[socketId] = callback;
          }
          // Return socket ID to caller (sync return value)
          // Note: actual connection is async, caller uses onSocket to wait for connect event
          return socketId;
        }

        case "onSocket": {
          // Register socket event callback
          var id = data.id;
          if (typeof callback === "function") {
            window.__j2meSocketCallbacks[id] = callback;
          }
          // Notify Swift to set up event forwarding
          window.webkit.messageHandlers.j2me.postMessage({
            type: "evalNative",
            command: "onSocket",
            data: data,
            hasCallback: typeof callback === "function"
          });
          break;
        }

        case "invokeSocket": {
          // Socket write/destroy - send to Swift (no callback expected)
          window.webkit.messageHandlers.j2me.postMessage({
            type: "evalNative",
            command: "invokeSocket",
            data: data,
            hasCallback: false
          });
          break;
        }

        default:
          console.warn("evalNative: unknown command", command);
      }
    };

    console.log("[iOS] evalNative network bridge initialized");
  })();
