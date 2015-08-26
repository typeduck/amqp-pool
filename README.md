# AMQP Pool

Create sets of AMQP consumers and publishers. JSON messages are routed using
(mustache) routing key templates, which are filled by the messages themselves.

***NOTE***: this API is very much under development and will probably change.

## Installation

    npm install amqp-pool

## Basic Usage

Create a specification of how you will consume and publish messages. Then call
this library to get started.


```javascript
var mq = require("amqp-pool")({
  server: "amqp://guest:guest@localhost"
  ,publishers: {
    life: "{kingdom}/{phylum}.{class}.{order}.{family}.{genus}.{species}"
  }
  ,consumers: {
    nutty: {
      routes: "Plants/#.Fagales.Fagaceae.#/#.Fagales.Betulaceae.#"
      ,method: function(msg){ console.log(msg); this.ack(msg) }
    }
    ,pears: {
      routes: [""]
      ,method: function(msg) { this.ack(msg); }
    }
  }
}).activate().then(function(){
  // now consuming and ready to publish
  mq.life.publish({
    kingdom: "Animalia"
    ,phylum: "Chordata"
    ,class: "Mammalia"
    ,order: "Primates"
    ,family: "Hominadae"
    ,genus: "Homo"
    ,species: "sapiens"
  })
}).catch(function(e){
  // OUCH, could NOT connect
})
```
