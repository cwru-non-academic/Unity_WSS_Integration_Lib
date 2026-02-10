using System.Collections;
using System.Collections.Generic;
using System.IO.Ports;
using TMPro;
using UnityEngine;

/// <summary>
/// Simple Unity helper that scans available serial ports and allows selecting
/// one from a UI dropdown to force the COM port used by the stimulation script.
/// Attach this to a separate GameObject and wire the <see cref="selectPort"/>
/// method to a UI event (e.g., button click) to apply the chosen port.
/// </summary>
/// <remarks>
/// Usage:
/// - Place this script on a separate GameObject (not a child of the stimulation object).
/// - Assign <see cref="stim"/> and <see cref="serialList"/> in the inspector.
/// - Ensure the stimulation script has <c>forcePort</c> enabled so the dropdown selection is used.
/// </remarks>
public class portScanner : MonoBehaviour
{
    /// <summary>
    /// Reference to the <see cref="Stimulation"/> component whose <c>comPort</c>
    /// will be set based on dropdown selection.
    /// </summary>
    [SerializeField] private Stimulation stim;
    /// <summary>
    /// Dropdown populated with detected serial port names.
    /// </summary>
    [SerializeField] private TMP_Dropdown serialList;

    private string selectedPort = "";

    /// <summary>
    /// Unity Start hook. No-op; the port list is generated on enable.
    /// </summary>
    void Start()
    {
        
    }

    /// <summary>
    /// Disables the stimulation component temporarily and populates the dropdown
    /// with available serial ports.
    /// </summary>
    void OnEnable()
    {
        stim.gameObject.SetActive(false);
        generatePortList();
    }

    /// <summary>
    /// Unity Update hook. No-op; present for completeness.
    /// </summary>
    void Update()
    {
        
    }

    /// <summary>
    /// Queries the system for serial ports and updates the dropdown options.
    /// Adds an "empty" placeholder when no ports are found.
    /// </summary>
    private void generatePortList()
    {
        serialList.ClearOptions();
        string[] ports = SerialPort.GetPortNames();
        if(ports.Length > 0)
        {
            List<string> portNames = new List<string>();
            foreach (string port in ports)
            {
                portNames.Add(port);
            }
            serialList.AddOptions(portNames);
        }else
        {
            serialList.options = new List<TMP_Dropdown.OptionData> { new TMP_Dropdown.OptionData("empty") };
        }
        serialList.SetValueWithoutNotify(0);
        serialList.RefreshShownValue();
    }

    /// <summary>
    /// Unity OnDisable hook. No-op.
    /// </summary>
    void OnDisable()
    {
        
    }

    /// <summary>
    /// Applies the selected COM port to the stimulation script and re-enables it.
    /// </summary>
    public void selectPort()
    {
        selectedPort = serialList.options[serialList.value].text;
        if(selectedPort != "empty")
        {
           stim.gameObject.SetActive(false);
           stim.comPort = selectedPort;
           stim.gameObject.SetActive(true);
        }
        
    }
}
