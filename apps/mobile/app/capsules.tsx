import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { router } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Action, styles } from '../components/ui';
import { useAuth } from '../lib/auth';
import { CapsuleListController, ListState } from '../lib/capsule-list';

const initialState: ListState = { items: [], phase: 'loading', error: '', hasMore: false };
const sessionKeys = new WeakMap<object, number>();
let nextSessionKey = 0;

function sessionKey(session: object): number {
  let key = sessionKeys.get(session);
  if (key === undefined) { key = ++nextSessionKey; sessionKeys.set(session, key); }
  return key;
}

function CapsuleList({ userId }: { userId: string }) {
  const [state, setState] = useState<ListState>(initialState);
  const controller = useRef<CapsuleListController | null>(null);
  useEffect(() => {
    const current = new CapsuleListController(userId, setState);
    controller.current = current;
    void current.refresh(true);
    return () => { current.dispose(); controller.current = null; };
  }, [userId]);

  return <SafeAreaView style={styles.screen}>
    <FlatList
      data={state.items}
      keyExtractor={(item) => item.id}
      contentContainerStyle={listStyles.content}
      refreshing={state.phase === 'refreshing'}
      onRefresh={() => void controller.current?.refresh()}
      ListHeaderComponent={<View style={listStyles.header}>
        <Text accessibilityRole="header" style={styles.title}>Your capsules</Text>
        <Text style={styles.text}>Status reflects the last time this list was refreshed.</Text>
      </View>}
      renderItem={({ item }) => <Pressable accessibilityRole="button" accessibilityLabel={`View capsule: ${item.title}`} onPress={() => router.push({ pathname: '/capsule/[id]', params: { id: item.id } })} style={listStyles.card}>
        <Text accessibilityRole="header" style={listStyles.cardTitle}>{item.title}</Text>
        <Text style={styles.text}>{item.status === 'locked' ? 'Locked' : 'Unlocked'}</Text>
        <Text style={styles.text}>Reveal time: {new Date(item.unlock_at).toLocaleString()}</Text>
      </Pressable>}
      ListEmptyComponent={state.phase === 'loading'
        ? <ActivityIndicator accessibilityLabel="Loading capsules" color="#A65338" />
        : state.phase === 'ready' ? <Text style={styles.text}>You have no capsules yet.</Text> : undefined}
      ListFooterComponent={<View style={listStyles.footer}>
        {state.error ? <><Text accessibilityRole="alert" style={styles.error}>{state.error}</Text>
          <Action title="Retry" onPress={() => void controller.current?.refresh()} /></> : null}
        {state.phase === 'loadingMore' && <ActivityIndicator accessibilityLabel="Loading more capsules" color="#A65338" />}
        {state.hasMore && state.phase === 'ready' && <Action title="Load more" onPress={() => void controller.current?.loadMore()} />}
        <Action title="Create a capsule" onPress={() => router.push('/create-capsule')} />
        <Action title="Back to home" onPress={() => router.replace('/home')} />
      </View>}
    />
  </SafeAreaView>;
}

export default function CapsulesScreen() {
  const { session } = useAuth();
  // A new session mounts a fresh controller and never renders the previous list.
  return session ? <CapsuleList key={sessionKey(session)} userId={session.user.id} /> : null;
}

const listStyles = StyleSheet.create({
  content: { flexGrow: 1, padding: 28, gap: 16, width: '100%', maxWidth: 480, alignSelf: 'center' },
  header: { gap: 16, marginBottom: 8 },
  card: { backgroundColor: '#FFFFFF', borderColor: '#DCC8B9', borderWidth: 1, borderRadius: 12, padding: 18, gap: 6 },
  cardTitle: { fontSize: 20, fontWeight: '600', color: '#332A25' },
  footer: { gap: 16, marginTop: 8 },
});
