"""Conversation, proposal review and composer presentation."""

import from endpoints { Board, CommandReply }
import from .date_labels { day_label }
import from react { useEffect }
import from studio { UiIcon, CompanionVisual }
import from .frontend_speech { SpeechSession }
import from .frontend_format { slack_label }
import from .frontend_panels { VoicePanel }

def ChatAvatar() -> JsxElement {
    return <div className="chat-avatar" aria-hidden="true"><CompanionVisual /></div>;
}

def:pub CommandPanel(view_board: Board, questions: list[str], answers: list[CommandReply], command_query: str, busy: bool, live_connected: bool, speech: SpeechSession, onQuery: any, run_command: any, open_workspace: any, accept_cmd_proposal: any, dismiss_cmd_proposal: any, sources: list[str] = [], onOfflineHelp: any = None) -> JsxElement {
    useEffect(lambda -> None {
        if len(answers) > 0 {
            thread: any = document.getElementById("command-conversation");
            if thread { thread.scrollTop = thread.scrollHeight; }
        }
    }, [answers]);
    return <section id="command" className="command-center" aria-labelledby="command-title">

                        <div className="command-body">
                            <span className="eyebrow">LET’S TALK ABOUT YOUR PLAN</span>
                            <h2 id="command-title">What is on your mind?</h2>


                            <div className="command-conversation-surface"><p className="secretary-connection">{"Live plan connected" if live_connected else "Live connection reconnecting. Refresh remains available."}</p>
                            <div id="command-conversation" className="command-thread" role="region" aria-label="Planning conversation" tabIndex={0}>
                                {len(answers) == 0 and <div className="assistant-message welcome-message"><ChatAvatar /><div className="assistant-welcome"><div><span>REPLANIVA ASSISTANT</span><p>What would you like to make room for?</p><small>Choose a suggestion or write a message below.</small></div></div></div>}

                                {[<article className="chat-exchange" key={str(index)}><div className="user-message"><span>You</span><p>{questions[index]}</p></div><div className="assistant-message" role="group" aria-label="Replaniva assistant"><ChatAvatar /><div className={"command-reply reply-" + answers[index].kind} role="status" aria-live="polite">
                                    <div>
                                        <span>{answers[index].kind.upper()} · {sources[index] if index < len(sources) else "Saved-plan answer"}</span>
                                        <div className="reply-header">
                                            <strong>{answers[index].title}</strong>
                                            <button type="button" className="speak-button" onClick={lambda -> None { speech.speak(answers[index].title + ". " + answers[index].message); return; }}><UiIcon name="volume-2" /><span className="sr-only">Read aloud</span></button>
                                            <button type="button" className="speak-button" disabled={not speech.speaking} aria-label="Stop reading aloud" onClick={speech.stop}><UiIcon name="volume-x" /><span className="sr-only">Stop reading aloud</span></button>
                                        </div>
                                        <p>{answers[index].message}</p>
                                    </div>
                                    {answers[index].action_target and <button type="button" className="card-link" onClick={lambda -> None { open_workspace(answers[index].action_target); }}>{answers[index].action_label}<UiIcon name="arrow-right" /></button>}
                                </div></div></article> for index in range(len(answers))]}
                                {len(view_board.command_proposals) > 0 and <div className="command-proposals-list">
                                    {[<div className="command-proposal-card" key={prop.id}>
                                        <div className="proposal-diff">
                                            <h4>{prop.title}</h4>
                                            <p>{prop.details}</p>
                                            <ul>
                                                {len(prop.affected_tasks) > 0 and <li>Affected tasks: {", ".join(prop.affected_tasks)}</li>}
                                                {prop.target_day and <li>Destination: {day_label(prop.target_day)}</li>}
                                                {prop.proposed_duration > 0 and <li>Proposed duration: {str(prop.proposed_duration)} minutes</li>}
                                                <li>Unplaced tasks: {prop.unplaced_count}</li>
                                                <li>Slack change: {slack_label(prop.slack_change)}</li>
                                            </ul>
                                        </div>
                                        <div className="proposal-actions">
                                            <button type="button" className="button primary" disabled={busy} onClick={lambda -> None { accept_cmd_proposal(prop.id); return; }}>Accept proposal</button>
                                            <button type="button" className="button secondary" disabled={busy} onClick={lambda -> None { dismiss_cmd_proposal(prop.id); return; }}>Dismiss</button>
                                        </div>
                                    </div> for prop in view_board.command_proposals]}
                                </div>}
                            </div></div>
<div className="command-composer">
                                <label className="composer-label" htmlFor="plan-command">{"Live transcript, review before sending" if speech.listening else "Your message"}</label>
                                <form onSubmit={run_command}>
                                    <div className="input-group">
                                        <textarea id="plan-command" rows={2} value={command_query} maxLength={300} placeholder="Ask about your day, or use the microphone..." aria-describedby="command-input-help" onChange={lambda (e: ChangeEvent) { onQuery(e.target.value); }} />
                                    </div>
                                    <button type="submit" disabled={busy or speech.listening or not command_query.strip()}><span className="sr-only">Send planning question</span><UiIcon name="arrow-up-right" /></button>
                                </form>
                                <VoicePanel listening={speech.listening} voice_supported={speech.supported} voice_error={speech.error} start_listening={speech.start} />
                                <p id="command-input-help" className="command-input-help">Voice fills this message. Review it, then send when you are ready.</p>{onOfflineHelp and <button className="offline-help-button" type="button" onClick={onOfflineHelp}>What works without Gemini?</button>}

                            </div>

                        </div>
                    </section>;
}
