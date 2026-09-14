package com.hitmakers.jenkins;

import hudson.Extension;
import hudson.console.LineTransformationOutputStream;
import hudson.model.Run;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import org.jenkinsci.plugins.workflow.flow.FlowExecutionOwner;
import org.jenkinsci.plugins.workflow.log.TaskListenerDecorator;

/** Only known, repetitive infrastructure chatter is condensed. Errors pass through. */
@Extension
public final class BackendConsoleFactory implements TaskListenerDecorator.Factory {
    @Override public TaskListenerDecorator of(FlowExecutionOwner owner) {
        try {
            if (!(owner.getExecutable() instanceof Run)) return null;
            String name = ((Run<?, ?>) owner.getExecutable()).getParent().getName();
            String base = System.getProperty("aof.backendJobName", "aof-back");
            if (name.equals(base) || name.equals(base + "-dev") || name.equals(base + "-feature") || name.equals(base + "-release")) {
                return new BackendDecorator();
            }
        } catch (IOException e) {
            // Logging must never break a build. Default to the original output.
        }
        return null;
    }
    public static final class BackendDecorator extends TaskListenerDecorator {
        private static final long serialVersionUID = 1L;
        @Override public OutputStream decorate(OutputStream logger) { return new Condensed(logger); }
    }
    public static final class Condensed extends LineTransformationOutputStream {
        private final OutputStream out;
        private final Map<String, String> previous = new HashMap<>();
        private final Map<String, Long> emitted = new HashMap<>();
        private String pod = "worker";
        public Condensed(OutputStream out) { this.out = out; }
        private void status(String key, String value) throws IOException {
            long now = System.currentTimeMillis();
            if (!value.equals(previous.get(key)) || now - emitted.getOrDefault(key, 0L) >= 60000L) {
                out.write(("[CI] " + value + "\n").getBytes(StandardCharsets.UTF_8));
                previous.put(key, value);
                emitted.put(key, now);
            }
        }
        @Override protected void eol(byte[] bytes, int length) throws IOException {
            String line = new String(bytes, 0, length, StandardCharsets.UTF_8);
            if (line.startsWith("[PodInfo] ")) { pod = line.trim().substring(10); return; }
            if (line.startsWith("\tPod [Pending][Unschedulable]")) {
                status(pod + "-schedule", "Waiting for an eligible ready worker. Scheduling detail: " + line.trim().substring("Pod [Pending][Unschedulable]".length()).trim());
                return;
            }
            if (line.startsWith("\tContainer [") && line.contains("waiting [ContainerCreating] No message")) {
                status(pod + "-creating", "Worker assigned; preparing agent containers."); return;
            }
            if (line.startsWith("\tPod [Pending][ContainersNotReady]")) return;
            // Preserve checkout commit/message and any error; omit routine Git invocations only.
            if (line.startsWith(" > git ") || line.startsWith("The recommended git tool is:") || line.startsWith("using GIT_ASKPASS ") || line.startsWith("Avoid second fetch")) return;
            out.write(bytes, 0, length);
        }
        @Override public void flush() throws IOException { out.flush(); }
        @Override public void close() throws IOException { super.close(); out.close(); }
    }
}
