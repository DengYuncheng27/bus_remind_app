{{flutter_js}}
{{flutter_build_config}}

// The root push worker already serves installed apps. Flutter's default
// migration worker can navigate a controlled client while it is starting.
function startupFailed(error) {
  console.error('Flutter startup failed', error);
  window.dispatchEvent(new Event('app-startup-error'));
}

_flutter.loader.load({
  onEntrypointLoaded: async initializer => {
    try {
      const app = await initializer.initializeEngine();
      await app.runApp();
    } catch (error) {
      startupFailed(error);
    }
  },
}).catch(startupFailed);
