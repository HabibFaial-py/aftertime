import { PropsWithChildren } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

export function Screen({ children }: PropsWithChildren) {
  return <SafeAreaView style={styles.screen}>
    <KeyboardAvoidingView style={styles.screen} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content}>{children}</ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

export function Action({ title, onPress, disabled = false }: { title: string; onPress: () => void; disabled?: boolean }) {
  return <Pressable accessibilityRole="button" accessibilityState={{ disabled }} disabled={disabled} onPress={onPress} style={({ pressed }) => [styles.button, { opacity: disabled || pressed ? 0.6 : 1 }]}>
    <Text style={styles.buttonText}>{title}</Text>
  </Pressable>;
}

export const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#FBF6EF' },
  content: { flexGrow: 1, justifyContent: 'center', padding: 28, gap: 20, width: '100%', maxWidth: 480, alignSelf: 'center' },
  title: { fontSize: 34, fontWeight: '600', color: '#332A25' },
  text: { fontSize: 17, lineHeight: 26, color: '#6A5C52' },
  label: { fontSize: 16, fontWeight: '600', color: '#332A25', marginBottom: 8 },
  input: { borderWidth: 1, borderColor: '#9A8170', borderRadius: 10, padding: 14, fontSize: 17, color: '#332A25', backgroundColor: '#FFFFFF' },
  button: { backgroundColor: '#A65338', borderRadius: 12, padding: 16, minHeight: 52, justifyContent: 'center' },
  buttonText: { fontSize: 17, fontWeight: '600', textAlign: 'center', color: '#FFFFFF' },
  link: { color: '#794431', fontSize: 17, paddingVertical: 12, textAlign: 'center' },
  error: { color: '#9B3025', fontSize: 16, lineHeight: 24 },
});
