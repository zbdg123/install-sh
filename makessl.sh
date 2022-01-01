
openssl genrsa -out ca.key 2048

openssl req -new -key ca.key -out ca.csr

openssl x509 -req -days 365 -in ca.csr -signkey ca.key -out ca.crt