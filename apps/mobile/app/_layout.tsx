import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { ActivityIndicator, Text } from 'react-native';
import { AuthProvider, useAuth } from '../lib/auth';
import { Action, Screen, styles } from '../components/ui';

function Routes() {
  const { session, loading, error, retry } = useAuth();
  if (loading) return <Screen><ActivityIndicator accessibilityLabel="Restoring session" color="#A65338" /></Screen>;
  if (error) return <Screen><Text style={styles.error}>{error}</Text><Action title="Retry" onPress={retry} /></Screen>;
  return <Stack screenOptions={{ headerShown: false, animation: 'none' }}>
    <Stack.Protected guard={!session}>
      <Stack.Screen name="index" />
      <Stack.Screen name="sign-in" />
      <Stack.Screen name="sign-up" />
      <Stack.Screen name="confirm-email" />
    </Stack.Protected>
    <Stack.Protected guard={!!session}><Stack.Screen name="home" /></Stack.Protected>
  </Stack>;
}

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <StatusBar style="dark" />
      <AuthProvider><Routes /></AuthProvider>
    </SafeAreaProvider>
  );
}
