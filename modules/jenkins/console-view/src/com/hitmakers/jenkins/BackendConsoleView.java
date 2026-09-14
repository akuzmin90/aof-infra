package com.hitmakers.jenkins;
import hudson.Extension;
import hudson.model.PageDecorator;
@Extension public final class BackendConsoleView extends PageDecorator {
    public String getBackendJobName() { return System.getProperty("aof.backendJobName", "aof-back"); }
}
