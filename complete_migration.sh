#!/bin/bash

# Complete Socket.IO to Pusher Migration Script
echo "🚀 Completing Socket.IO to Pusher migration..."

# Update remaining references in AuthProvider
echo "📝 Updating AuthProvider..."
sed -i '' 's/_globalSocketService/_pusherService/g' lib/providers/auth_provider.dart

# Update remaining references in GlobalEventProvider  
echo "📝 Updating GlobalEventProvider..."
sed -i '' 's/_globalSocketService/_pusherService/g' lib/providers/global_event_provider.dart

# Update remaining references in ChatDetailsScreen
echo "📝 Updating ChatDetailsScreen..."
sed -i '' 's/_globalSocketService/_pusherService/g' lib/views/consversations/chatdetailsscreen.dart

# Search for any remaining references
echo "🔍 Checking for remaining Socket.IO references..."
echo "Files with GlobalSocketService references:"
grep -r "GlobalSocketService" lib/ --exclude-dir=services || echo "✅ No GlobalSocketService references found"

echo "Files with _globalSocketService references:"
grep -r "_globalSocketService" lib/ --exclude-dir=services || echo "✅ No _globalSocketService references found"

echo "Files with SocketService references:"
grep -r "SocketService" lib/ --exclude-dir=services --exclude="pusher_service.dart" || echo "✅ No SocketService references found"

# Check for any socket_io_client imports
echo "Files with socket_io_client imports:"
grep -r "socket_io_client" lib/ || echo "✅ No socket_io_client imports found"

echo ""
echo "🎉 Migration completion script finished!"
echo ""
echo "📋 Next steps:"
echo "1. Run 'flutter pub get' to ensure dependencies are updated"
echo "2. Test the app for any compilation errors"
echo "3. Test realtime messaging functionality"
echo "4. Remove old socket service files when everything works:"
echo "   - rm lib/services/global_socket_service.dart"
echo "   - rm lib/services/socket_service.dart"
echo ""
echo "✨ The Pusher migration should now be complete!" 