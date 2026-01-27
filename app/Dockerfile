# Use a Node.js base image
FROM node:18-alpine

# Set working directory
WORKDIR /usr/src/app

# Copy application code
COPY app.js .

# Expose port
EXPOSE 8080

# Start the application
CMD ["node", "app.js"]
