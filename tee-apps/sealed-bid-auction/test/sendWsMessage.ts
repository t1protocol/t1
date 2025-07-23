// if testing on localhost, disable SSL/TLS for simplicity of testing
const socket = new WebSocket("ws://localhost:3010/", {
    headers: {
        Authorization: "Bob"
    }
});

while (socket.readyState !== 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    console.log('.');
}

socket.send("Hello my dude!");
console.log("I sent a message to WebSocket!");
socket.close();