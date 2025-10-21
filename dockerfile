# Use Nginx official image to serve static content
FROM nginx:alpine

# Copy your HTML files to Nginx's default web directory
COPY . /usr/share/nginx/html

# Expose port 80 (Nginx default)
EXPOSE 80

# No need for CMD — nginx:alpine already starts Nginx by default
