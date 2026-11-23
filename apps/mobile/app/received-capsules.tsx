import { useCallback, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { ReceivedCapsulesContent } from '../components/received-capsules';
import { Action, Screen, styles } from '../components/ui';
import { useAuth } from '../lib/auth';
import { directCapsulesEnabled } from '../lib/direct-feature';
import { ReceivedCapsulesController, ReceivedState } from '../lib/received-capsules';
import { createReceivedPreview, receivedPreviewScenarios, ReceivedPreviewScenario } from '../lib/received-preview';

const sessionKeys = new WeakMap<object, number>();
let nextSessionKey = 0;

function sessionKey(session: object) {
  let key = sessionKeys.get(session);
  if (key === undefined) { key = ++nextSessionKey; sessionKeys.set(session, key); }
  return key;
}

function PreviewInbox({ scenario }: { scenario: ReceivedPreviewScenario }) {
  const [state, setState] = useState<ReceivedState>({ phase: 'loading' });
  const controller = useRef<ReceivedCapsulesController | null>(null);
  useFocusEffect(useCallback(() => {
    const current = new ReceivedCapsulesController(createReceivedPreview(scenario), setState);
    controller.current = current;
    void current.refresh();
    return () => {
      current.dispose();
      controller.current = null;
      setState({ phase: 'loading' });
    };
  }, [scenario]));

  return <ReceivedCapsulesContent state={state} onRefresh={() => void controller.current?.refresh()}
    onReveal={(id) => void controller.current?.reveal(id)} />;
}

function LocalPreview() {
  const [scenario, setScenario] = useState<ReceivedPreviewScenario>('inbox');
  const [expanded, setExpanded] = useState(false);
  return <>
    <PreviewInbox key={scenario} scenario={scenario} />
    <Pressable accessibilityRole="button" accessibilityState={{ expanded }} onPress={() => setExpanded(!expanded)}>
      <Text style={styles.link}>Local preview states</Text>
    </Pressable>
    {expanded && <View style={previewStyles.options}>
      {receivedPreviewScenarios.map((option) => <Pressable key={option.id} accessibilityRole="button"
        accessibilityState={{ selected: option.id === scenario }} onPress={() => { setScenario(option.id); setExpanded(false); }}
        style={[previewStyles.option, option.id === scenario && previewStyles.selected]}>
        <Text style={styles.text}>{option.label}</Text>
      </Pressable>)}
    </View>}
  </>;
}

export default function ReceivedCapsulesScreen() {
  const { session } = useAuth();
  if (!session || !directCapsulesEnabled) return null;
  return <Screen topAligned>
    <Text accessibilityRole="header" style={styles.title}>Received Capsules</Text>
    {__DEV__ ? <LocalPreview key={sessionKey(session)} /> : <ReceivedCapsulesContent state={{ phase: 'unavailable' }} />}
    <Action title="Back to home" onPress={() => router.replace('/home')} />
  </Screen>;
}

const previewStyles = StyleSheet.create({
  options: { gap: 8 },
  option: { borderColor: '#9A8170', borderWidth: 1, borderRadius: 10, padding: 10, minHeight: 48, justifyContent: 'center' },
  selected: { backgroundColor: '#F0DFD2' },
});
