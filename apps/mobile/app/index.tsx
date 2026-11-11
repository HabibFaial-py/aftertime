import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { Action } from '../components/ui';
import { useAuth } from '../lib/auth';

export default function WelcomeScreen() {
  const { expired } = useAuth();
  return (
    <SafeAreaView style={styles.screen}>
      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.welcome}>
          <View accessible={false} style={styles.emblem}>
            <View style={styles.seed} />
          </View>
          <Text accessibilityRole="header" style={styles.title}>AfterTime</Text>
          <Text style={styles.tagline}>Write today. Reveal tomorrow.</Text>
          <View accessible={false} style={styles.divider} />
          <Text style={styles.description}>
            A little space for words worth waiting for.
          </Text>
          <View style={{ gap: 12, marginTop: 28, width: '100%' }}>
            {expired && <Text style={styles.description}>Your session expired. Connect to the internet or sign in again.</Text>}
            <Action title="Sign in" onPress={() => router.push('/sign-in')} />
            <Action title="Create an account" onPress={() => router.push('/sign-up')} />
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#FBF6EF' },
  content: { flexGrow: 1, justifyContent: 'center', padding: 32 },
  welcome: { alignItems: 'center', alignSelf: 'center', maxWidth: 420, width: '100%' },
  emblem: {
    width: 88, height: 88, borderRadius: 44, backgroundColor: '#F0DFD2',
    alignItems: 'center', justifyContent: 'center', marginBottom: 32,
  },
  seed: { width: 26, height: 38, borderRadius: 20, backgroundColor: '#A65338', transform: [{ rotate: '30deg' }] },
  title: { fontSize: 44, fontWeight: '600', letterSpacing: -1.5, color: '#332A25', textAlign: 'center' },
  tagline: { marginTop: 16, fontSize: 19, lineHeight: 29, color: '#794431', textAlign: 'center' },
  divider: { width: 32, height: 2, backgroundColor: '#A65338', marginVertical: 28 },
  description: { maxWidth: 260, fontSize: 16, lineHeight: 25, color: '#6A5C52', textAlign: 'center' },
});
