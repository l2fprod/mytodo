/**
 * Copyright 2016 IBM Corp. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the “License”);
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an “AS IS” BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
const mongodb = require('mongodb');
const fs = require('fs');
const MongoClient = mongodb.MongoClient;

function DB(credentials) {
  console.log(credentials);
  const DB_NAME = 'todos';
  const COLLECTION_NAME = 'todos';
  const self = this;
  let db;

  self.type = function() {
    return 'Databases for MongoDB';
  };

  self.init = () => {
    return new Promise((resolve, reject) => {
      let connectionString;
      if (credentials.connectionUrl) {
        connectionString = credentials.connectionUrl;
      } else {
        // Extract the database username and password
        let username = credentials.MONGO_USERNAME;
        let password = credentials.MONGO_PASSWORD;
        // Extract the MongoDB URIs
        let connectionPath = credentials.MONGO_HOSTS;
        connectionString = `mongodb://${username}:${password}@${connectionPath}/?replicaSet=replset`;
      }

      // write down the certificate so that it can be used by MongoDB client
      fs.writeFileSync('mongo.crt', Buffer.from(credentials.MONGO_CERTIFICATE_BASE64, 'base64'));
      // console.log(connectionString);

      // We always want to make a validated TLS/SSL connection
      var options = {
        tls: true,
        // sslValidate: true,
        // tlsCAFile: 'mongo.crt',
        // sslCA: 'mongo.crt',
        // maxPoolSize: 1,
        tlsAllowInvalidCertificates: true,
        // useNewUrlParser: true,
        // useUnifiedTopology: true
      };
      const client = new MongoClient(connectionString, options);
      client.connect((err, mongoDb) => {
        console.log(mongoDb);
        if (err) {
          console.log(err);
          reject(err);
        } else {
          console.log("Connected to MongoDB");
          db = mongoDb.db(DB_NAME).collection(COLLECTION_NAME);
          resolve();
        }
      });
      console.log("Connecting to MongoDB...");
    })
  };

  self.count = () => {
    console.log('count');
    return new Promise((resolve, reject) => {
      db.count((err, count) => {
        if (err) {
          reject(err);
        } else {
          console.log('counted', count);
          resolve(count);
        }
      });
    });
  };

  self.search = () => {
    console.log('search');
    return new Promise((resolve, reject) => {
      db.find().toArray((err, result) => {
        if (err) {
          reject(err);
        } else {
          console.log('searched', result);
          resolve(result.map(todo => {
            todo.id = todo._id;
            delete todo._id;
            return todo;
          }));
        }
      });
    });
  };

  self.create = (item) => {
    console.log('create', item);
    return new Promise((resolve, reject) => {
      db.insertOne(item, (err, result) => {
        if (err) {
          reject(err);
        } else {
          const newItem = {
            id: result.insertedId,
            title: item.title,
            completed: item.completed,
            order: item.order
          };
          console.log('created', newItem);
          resolve(newItem);
        }
      });
    });
  };

  self.read = (id) => {
    console.log('read', id);
    return new Promise((resolve, reject) => {
      db.findOne({ _id: new mongodb.ObjectID(id) }, (err, item) => {
        if (err) {
          reject(err);
        } else {
          item.id = item._id;
          delete item._id;
          console.log('read', item);
          resolve(item);
        }
      });
    });
  };

  self.update = (id, newValue) => {
    console.log('update', id, newValue);
    return new Promise((resolve, reject) => {
      delete newValue.id;
      db.findAndModify({ _id: new mongodb.ObjectID(id) }, [], newValue, { upsert: true }, (err, updatedItem) => {
        if (err) {
          reject(err);
        } else {
          newValue.id = id;
          delete newValue._id;
          console.log('updated', newValue);
          resolve(newValue);
        }
      });
    });
  };

  self.delete = (id) => {
    console.log('delete', id);
    return new Promise((resolve, reject) => {
      db.deleteOne({ _id: new mongodb.ObjectID(id) }, (err, result) => {
        if (err) {
          reject(err);
        } else {
          console.log('deleted', id);
          resolve({ id: id });
        }
      });
    });
  };
}

module.exports = function(credentials) {
  return new DB(credentials);
}
