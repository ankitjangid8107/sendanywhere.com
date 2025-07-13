# File Sharing Application - replit.md

## Overview

This is a modern file sharing web application built with a React frontend and Express.js backend. The application allows users to upload files and share them via download codes or direct links, with automatic expiration and cleanup features. It features a professional UI built with shadcn/ui components and Tailwind CSS.

## User Preferences

Preferred communication style: Simple, everyday language.
Creator/Developer: Ankit Jangid
File size limit: Increased to 30GB maximum upload size

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Routing**: Wouter for client-side routing
- **State Management**: TanStack Query (React Query) for server state management
- **UI Components**: shadcn/ui component library built on Radix UI primitives
- **Styling**: Tailwind CSS with custom CSS variables for theming
- **Build Tool**: Vite for development and production builds

### Backend Architecture
- **Framework**: Express.js with TypeScript
- **File Upload**: Multer for handling multipart/form-data file uploads
- **Storage**: In-memory storage implementation with file system storage for uploaded files
- **Database**: Drizzle ORM configured for PostgreSQL (schema defined but using in-memory storage currently)
- **Session Management**: Express sessions with PostgreSQL session store (connect-pg-simple)

## Key Components

### Database Schema
The application defines two main entities:
- **Users**: Basic user management with username/password authentication
- **Files**: File metadata including original name, size, MIME type, download codes, and expiration timestamps

### File Management
- **Upload Process**: Files are stored in an `uploads` directory with unique filenames
- **Download Codes**: 6-character alphanumeric codes generated for each file
- **Expiration**: Files automatically expire after 24 hours
- **Cleanup**: Background process removes expired files every hour

### UI Components
- **File Upload**: Drag-and-drop interface with progress tracking
- **Download Interface**: Code input system with 6-digit verification
- **Responsive Design**: Mobile-first approach with responsive breakpoints
- **Theming**: Light/dark mode support with CSS custom properties

## Data Flow

1. **File Upload**:
   - User selects/drops files in the upload component
   - Files are validated for size and type
   - Upload progress is tracked via XMLHttpRequest
   - Server generates unique download code and stores file metadata
   - User receives download code and shareable link

2. **File Download**:
   - User enters 6-digit download code or visits direct link
   - System validates code and checks expiration
   - File is served for download and marked as downloaded
   - File is automatically cleaned up after expiration

3. **Background Processes**:
   - Cleanup job runs hourly to remove expired files
   - File system and database entries are synchronized

## External Dependencies

### Frontend Dependencies
- **React Ecosystem**: React 18, React DOM, React Query
- **UI Libraries**: Radix UI primitives, Lucide React icons
- **Utilities**: date-fns for date manipulation, clsx for conditional classes
- **Development**: Vite, TypeScript, Tailwind CSS

### Backend Dependencies
- **Core**: Express.js, Multer for file uploads
- **Database**: Drizzle ORM, @neondatabase/serverless for PostgreSQL
- **Utilities**: Zod for schema validation, nanoid for ID generation
- **Session**: connect-pg-simple for PostgreSQL session storage

## Deployment Strategy

### Development
- **Frontend**: Vite dev server with HMR
- **Backend**: tsx for TypeScript execution with nodemon-like restart
- **Database**: PostgreSQL connection via environment variable

### Production
- **Build Process**: 
  - Frontend: Vite build to `dist/public`
  - Backend: esbuild bundle to `dist/index.js`
- **Static Files**: Express serves built frontend from `dist/public`
- **File Storage**: Local file system in `uploads` directory
- **Database**: PostgreSQL via DATABASE_URL environment variable

### Configuration
- **Environment Variables**: DATABASE_URL for PostgreSQL connection
- **File Limits**: 30GB maximum file size (increased from 100MB)
- **Session Configuration**: PostgreSQL-backed sessions for scalability
- **CORS**: Configured for cross-origin requests if needed
- **Branding**: Updated to "FileFluxTransfer by Ankit Jangid"

The application is designed to be easily deployable to platforms like Replit, Heroku, or similar Node.js hosting services with PostgreSQL add-ons.