import { ipcChannels, type DesktopBridge } from '@turtle-base/platform';
import { contextBridge, ipcRenderer } from 'electron';

const allowed = new Set<string>(ipcChannels);

// The renderer gets exactly the channels of IpcContract - nothing of Node or Electron itself.
const bridge: DesktopBridge = {
  invoke: (channel, ...args) =>
    allowed.has(channel)
      ? ipcRenderer.invoke(channel, ...args)
      : Promise.reject(new Error(`Unknown channel ${channel}`)),
};

contextBridge.exposeInMainWorld('turtleDesktop', bridge);
