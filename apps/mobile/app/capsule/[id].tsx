import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { Action, Screen, styles } from '../../components/ui';
import { useAuth } from '../../lib/auth';
import { CapsuleDetailController, DetailState, emptyDetail, validCapsuleId } from '../../lib/capsule-detail';

const sessionKeys = new WeakMap<object, number>();
let nextKey = 0;
function sessionKey(session: object) {
  let key = sessionKeys.get(session);
  if (key === undefined) { key = ++nextKey; sessionKeys.set(session, key); }
  return key;
}

function Detail({ userId, id }: { userId: string; id: string }) {
  const [state, setState] = useState<DetailState>(emptyDetail);
  const controller = useRef<CapsuleDetailController | null>(null);
  useFocusEffect(useCallback(() => {
    const current = new CapsuleDetailController(userId, id, setState);
    controller.current = current;
    void current.load();
    return () => {
      current.dispose();
      controller.current = null;
      setState(emptyDetail());
    };
  }, [userId, id]));

  async function cancelConfirmed() {
    const current = controller.current;
    if (current && await current.confirmCancellation() && controller.current === current) router.replace('/capsules');
  }

  return <Screen>
    <Text accessibilityRole="header" style={styles.title}>Capsule</Text>
    {state.phase === 'loading' && <ActivityIndicator accessibilityLabel="Loading capsule" color="#A65338" />}
    {state.metadata && <>
      <Text accessibilityRole="header" style={styles.label}>{state.metadata.title}</Text>
      <Text style={styles.text}>Status: {state.metadata.status === 'locked' ? 'Locked' : 'Unlocked'}</Text>
      <Text style={styles.text}>Reveal time: {new Date(state.metadata.unlock_at).toLocaleString()}</Text>
      <Text style={styles.text}>Status reflects the last metadata refresh. The server decides when a message can be revealed.</Text>
    </>}
    {state.phase === 'unavailable' && <Text style={styles.text}>This capsule is unavailable.</Text>}
    {state.error ? <Text accessibilityRole="alert" style={styles.error}>{state.error}</Text> : null}
    {state.phase === 'revealing' && <ActivityIndicator accessibilityLabel="Revealing message" color="#A65338" />}
    {state.phase === 'revealed' && state.body !== null && <Text accessibilityLabel="Revealed message" style={styles.text}>{state.body}</Text>}
    {state.metadata && (state.phase === 'ready' || state.phase === 'error') && <Action title="Reveal message" onPress={() => void controller.current?.reveal()} />}
    {state.metadata && (state.phase === 'ready' || state.phase === 'revealed' || state.phase === 'error') && <Pressable accessibilityRole="button" onPress={() => controller.current?.requestCancellation()} style={cancelStyles.button}>
      <Text style={cancelStyles.text}>Cancel capsule</Text>
    </Pressable>}
    {state.phase === 'confirmCancel' && <>
      <Text accessibilityRole="header" style={styles.label}>Cancel this capsule?</Text>
      <Text style={styles.text}>Cancellation is permanent. The capsule cannot be revealed afterward. Cancellation is only available while permitted by the server.</Text>
      <Pressable accessibilityRole="button" onPress={() => void cancelConfirmed()} style={cancelStyles.button}><Text style={cancelStyles.text}>Confirm cancellation</Text></Pressable>
      <Action title="Keep capsule" onPress={() => controller.current?.keepCapsule()} />
    </>}
    {state.phase === 'cancelling' && <ActivityIndicator accessibilityLabel="Cancelling capsule" color="#A65338" />}
    {state.phase === 'cancelled' && <Text style={styles.text}>Capsule cancelled.</Text>}
    {!state.metadata && state.phase === 'error' && <Action title="Retry" onPress={() => void controller.current?.load()} />}
    <Action title="Back to capsules" disabled={state.phase === 'cancelling'} onPress={() => router.replace('/capsules')} />
  </Screen>;
}

const cancelStyles = StyleSheet.create({
  button: { borderWidth: 2, borderColor: '#9B3025', borderRadius: 12, padding: 16, minHeight: 52, justifyContent: 'center' },
  text: { color: '#9B3025', fontSize: 17, fontWeight: '600', textAlign: 'center' },
});

export default function CapsuleDetailScreen() {
  const { session } = useAuth();
  const { id } = useLocalSearchParams<{ id?: string | string[] }>();
  if (!session) return null;
  // Invalid or multiple route values never reach the API.
  const routeId = validCapsuleId(id) ? id : '';
  return <Detail key={`${sessionKey(session)}:${routeId}`} userId={session.user.id} id={routeId} />;
}
