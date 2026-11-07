// Only engine services are shimmed. Tests invoke the actual production host
// lifecycle methods; these results do not represent a Unity Editor/Play run.
using System;
namespace UnityEngine
{
    public class MonoBehaviour { public bool isActiveAndEnabled { get; set; } = true; }
    public interface ISerializationCallbackReceiver { void OnBeforeSerialize(); void OnAfterDeserialize(); }
    public sealed class SerializeField : Attribute { }
    public sealed class TooltipAttribute : Attribute { public TooltipAttribute(string value) { } }
    public sealed class HideInInspector : Attribute { }
    public static class Application { public static string streamingAssetsPath; }
    public enum KeyCode { A }
    public static class Input
    {
        internal static bool NextA;
        public static bool GetKeyDown(KeyCode key) { bool result = NextA; NextA = false; return result; }
    }
    public static class Debug
    {
        public static void Log(object value, object context = null) { }
        public static void LogWarning(object value, object context = null) { }
        public static void LogError(object value, object context = null) { }
    }
}
namespace UnityEngine.Serialization
{
    [AttributeUsage(AttributeTargets.Field, AllowMultiple = true)]
    public sealed class FormerlySerializedAsAttribute : Attribute { public FormerlySerializedAsAttribute(string value) { } }
}
