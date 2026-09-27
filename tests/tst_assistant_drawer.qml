import QtQuick
import Qt.labs.folderlistmodel
import "../theme"
import "../components"
import "../config"
import "../assistant"
import "../assistant/components"

Item {
    id: testRoot
    width: 1200
    height: 900

    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(cond, msg) {
        if (!cond) {
            console.error("FAIL: " + msg);
            Qt.exit(1);
            throw new Error(msg);
        }
        return true;
    }

    AssistantDrawer {
        id: drawer
        testMode: true
        isOpen: true
    }

    AssistantDrawer {
        id: floatingDrawer
        testMode: true
        isFloating: true
        isOpen: true
    }

    AssistantDrawer {
        id: splitDrawer
        testMode: true
        isFloating: true
        isOpen: true
        sessionsVisible: true
    }

    ToolConfirmationCard {
        id: testCard
        toolProposal: ({
            id: "call_test",
            tool_name: "bash",
            command: "sudo systemctl restart NetworkManager",
            args: [],
            is_dangerous: true,
            requires_sudo: true
        })
    }

    QuickActionChips {
        id: testChips
    }

    ModelProviderBar {
        id: testBar
    }

    ChatInputBar {
        id: testInputBar
    }

    MermaidDiagramCard {
        id: testMermaidCard
        mermaidSource: "graph TD\n  A[Start] --> B[Finish]"
    }

    ToolConfirmationCard {
        id: testImageCard
        toolProposal: ({
            id: "call_img_inspect",
            tool_name: "read_file",
            command: "/tmp/sample_vision.png",
            args: [],
            is_dangerous: false,
            requires_sudo: false
        })
    }

    SessionListDrawer {
        id: testSessionDrawer
    }

    LiquidGlassFilePicker {
        id: testPicker
    }

    function runTests() {
        console.log("Running tst_assistant_drawer.qml test suite...");

        // 1. Geometry assertions
        assert(drawer.drawerWidth === 460, "Drawer width must be 460px");
        assert(drawer.width === 460, "Drawer item width must equal drawerWidth");
        assert(drawer.isOpen === true, "Drawer must be open in test state");

        // 2. Open placement
        assert(drawer.x === (testRoot.width - drawer.drawerWidth), "Drawer x must align to right screen edge when open");

        // 3. Motion state
        drawer.isOpen = false;
        assert(drawer.isOpen === false, "Drawer state must reflect closed");

        // 4. Tool Confirmation Card
        assert(testCard.toolProposal !== null, "Tool proposal must be bound");
        assert(testCard.toolProposal.requires_sudo === true, "Tool proposal must reflect sudo requirement");
        assert(testCard.toolProposal.command.indexOf("systemctl") !== -1, "Command text must be retained");
        assert(testCard.toolProposal.is_dangerous === true, "Tool proposal must reflect dangerous flag");

        // 5. Quick Action Chips
        assert(testChips.chips && testChips.chips.length >= 4, "Must offer at least 4 predefined diagnostic chips");
        assert(testChips.chips[0].label === "Diagnose Errors", "First chip must be Diagnose Errors");

        // 6. Model & Provider Selector Bar
        assert(testBar.implicitHeight === 44, "ModelProviderBar height must be 44");
        assert(testBar.providerName.length > 0, "ModelProviderBar must display active provider name");
        assert(testBar.currentModel.length > 0, "ModelProviderBar must display active model");

        // 7. AssistantService Source Contract
        const serviceSrc = readLocalFile("../services/AssistantService.qml");
        assert(serviceSrc.length > 500, "services/AssistantService.qml must be readable");
        assert(/pragma Singleton/.test(serviceSrc), "AssistantService must be a Singleton");
        assert(/property string selectedHarness/.test(serviceSrc), "AssistantService must track selectedHarness");
        assert(/property string selectedProviderId/.test(serviceSrc), "AssistantService must track selectedProviderId");
        assert(/property string selectedModelId/.test(serviceSrc), "AssistantService must track selectedModelId");
        assert(/function selectProvider\(/.test(serviceSrc), "AssistantService must implement selectProvider");
        assert(/function selectModel\(/.test(serviceSrc), "AssistantService must implement selectModel");
        assert(/function getModelsForProvider\(/.test(serviceSrc), "AssistantService must implement getModelsForProvider");
        assert(/function sendMessage\(/.test(serviceSrc), "AssistantService must implement sendMessage");
        assert(/function approveToolCall\(/.test(serviceSrc), "AssistantService must implement approveToolCall");
        assert(/function denyToolCall\(/.test(serviceSrc), "AssistantService must implement denyToolCall");
        assert(/function diagnoseCrash\(/.test(serviceSrc), "AssistantService must implement diagnoseCrash");
        assert(/function refreshSkills\(/.test(serviceSrc), "AssistantService must implement refreshSkills");
        assert(/function refreshCrashes\(/.test(serviceSrc), "AssistantService must implement refreshCrashes");
        assert(/property var dismissedCrashIds/.test(serviceSrc), "AssistantService must declare dismissedCrashIds");
        assert(/readonly property var activeCrashes/.test(serviceSrc), "AssistantService must declare activeCrashes");
        assert(/function dismissCrash\(/.test(serviceSrc), "AssistantService must implement dismissCrash");
        assert(/function dismissAllCrashes\(/.test(serviceSrc), "AssistantService must implement dismissAllCrashes");

        // 7. Predefined Skills Verification
        const diagSkill = readLocalFile("../skills/system-diagnostics/SKILL.md");
        assert(diagSkill.length > 100, "system-diagnostics skill must exist");
        assert(/coredumpctl/.test(diagSkill), "system-diagnostics skill must reference coredumpctl");

        const procSkill = readLocalFile("../skills/process-optimizer/SKILL.md");
        assert(procSkill.length > 100, "process-optimizer skill must exist");

        const audioSkill = readLocalFile("../skills/audio-display-troubleshooter/SKILL.md");
        assert(audioSkill.length > 100, "audio-display-troubleshooter skill must exist");

        const pkgSkill = readLocalFile("../skills/package-cache-manager/SKILL.md");
        assert(pkgSkill.length > 100, "package-cache-manager skill must exist");

        // 8. Floating Mode & Centering Assertions
        assert(floatingDrawer.isFloating === true, "floatingDrawer must have isFloating enabled");
        assert(floatingDrawer.width > 460, "floatingDrawer width must scale with screen width");
        assert(floatingDrawer.x === Math.round((testRoot.width - floatingDrawer.width) / 2), "floatingDrawer must be horizontally centered");
        assert(floatingDrawer.y === Math.round((testRoot.height - floatingDrawer.height) / 2), "floatingDrawer must be vertically centered");

        // 9. Floating Window & Non-Modal Pass-Through Contract (No Underlay, No Outside Dismissal)
        const windowSrc = readLocalFile("../assistant/AssistantWindow.qml");
        assert(windowSrc.length > 300, "assistant/AssistantWindow.qml must be readable");
        assert(/isFloating:\s*true/.test(windowSrc), "AssistantWindow must declare isFloating: true on AssistantDrawer");
        assert(/color:\s*"transparent"/.test(windowSrc), "AssistantWindow must have transparent color without underlay dim scrim");
        assert(/mask:\s*Region/.test(windowSrc), "AssistantWindow must declare mask Region to restrict clicks to floating card and allow pass-through");
        assert(!/MouseArea\s*\{[\s\S]*?Config\.closeAssistant\(\)/.test(windowSrc), "AssistantWindow must not have outside dismissal MouseArea");
        assert(/BackgroundEffect\.blurRegion/.test(windowSrc), "AssistantWindow must apply compositor blurRegion to floating card");

        // 10. Streaming Content Reactivity Contract
        const chatViewSrc = readLocalFile("../assistant/components/ChatView.qml");
        assert(chatViewSrc.length > 500, "assistant/components/ChatView.qml must be readable");
        assert(/activeStreamingContent/.test(chatViewSrc), "ChatView must reactively bind to activeStreamingContent");
        assert(/messagesRevision/.test(chatViewSrc), "ChatView must reactively track messagesRevision");
        assert(/messagesRevision/.test(serviceSrc), "AssistantService must provide messagesRevision property");

        // 11. Draggable & High-Contrast Visual Clarity Contract
        const drawerSrc = readLocalFile("../assistant/AssistantDrawer.qml");
        assert(drawerSrc.length > 500, "assistant/AssistantDrawer.qml must be readable");
        assert(floatingDrawer.userMoved === false, "floatingDrawer userMoved must start false");
        assert(typeof floatingDrawer.resetPosition === "function", "AssistantDrawer must expose resetPosition function");
        assert(/headerItem/.test(drawerSrc) && /dragTarget/.test(drawerSrc), "AssistantDrawer must bind dragTarget to headerItem for header-based window dragging");
        assert(/dialogDragArea/.test(drawerSrc), "AssistantDrawer must declare dialogDragArea for background surface dragging");
        assert(/drag\.target:\s*root\.isFloating\s*\?\s*root\s*:\s*null/.test(drawerSrc), "AssistantDrawer must set drag.target to root when floating");
        assert(/0\.82/.test(drawerSrc), "AssistantDrawer must use Ghostty-style slight transparency frosted glass substrate (82% alpha)");
        assert(/userMoved/.test(windowSrc), "AssistantWindow must track userMoved state");
        assert(/clampPosition/.test(windowSrc), "AssistantWindow must implement boundary clampPosition");

        // Verify position reset logic
        const initialX = floatingDrawer.x;
        const initialY = floatingDrawer.y;
        floatingDrawer.x = 100;
        floatingDrawer.y = 80;
        floatingDrawer.userMoved = true;
        assert(floatingDrawer.x === 100 && floatingDrawer.y === 80, "floatingDrawer must support manual coordinate positioning");
        floatingDrawer.resetPosition();
        assert(floatingDrawer.userMoved === false, "resetPosition must reset userMoved flag");
        assert(floatingDrawer.x === initialX, "resetPosition must restore centered x coordinate");
        assert(floatingDrawer.y === initialY, "resetPosition must restore centered y coordinate");

        // 12. Send Button Visibility & Interaction Contract
        const inputBarSrc = readLocalFile("../assistant/components/ChatInputBar.qml");
        assert(inputBarSrc.length > 500, "assistant/components/ChatInputBar.qml must be readable");
        assert(/sendButton/.test(inputBarSrc), "ChatInputBar must declare sendButton");
        assert(/iconName:\s*sendButton\.isStreaming\s*\?\s*"stop"\s*:\s*"send"/.test(inputBarSrc), "ChatInputBar must bind send/stop icon dynamically");
        assert(/Colors\.glassBorderSpecular/.test(inputBarSrc), "sendButton must have visible specular border");
        assert(/submitMessage/.test(inputBarSrc), "ChatInputBar must submit message when clicked");

        // 13. Resizability & Minimum Dimension Constraints
        assert(floatingDrawer.minWidth === 480, "AssistantDrawer minWidth must be 480px");
        assert(floatingDrawer.minHeight === 520, "AssistantDrawer minHeight must be 520px");
        assert(floatingDrawer.customWidth >= 0, "AssistantDrawer must expose customWidth");
        assert(floatingDrawer.customHeight >= 0, "AssistantDrawer must expose customHeight");
        assert(/rightResizeHandle/.test(drawerSrc), "AssistantDrawer must declare rightResizeHandle");
        assert(/bottomResizeHandle/.test(drawerSrc), "AssistantDrawer must declare bottomResizeHandle");
        assert(/leftResizeHandle/.test(drawerSrc), "AssistantDrawer must declare leftResizeHandle");
        assert(/cornerResizeHandle/.test(drawerSrc), "AssistantDrawer must declare cornerResizeHandle");

        // Test custom resize
        floatingDrawer.customWidth = 640;
        floatingDrawer.customHeight = 700;
        assert(floatingDrawer.width === 640, "floatingDrawer width must reflect customWidth");
        assert(floatingDrawer.height === 700, "floatingDrawer height must reflect customHeight");

        // 14. Image Ingestion & In-Chat Previews Contract
        assert(testInputBar.stagedImages !== undefined, "ChatInputBar must expose stagedImages");
        assert(typeof testInputBar.stageImage === "function", "ChatInputBar must implement stageImage");
        assert(typeof testInputBar.unstageImage === "function", "ChatInputBar must implement unstageImage");

        testInputBar.stageImage("/tmp/test_image.png");
        assert(testInputBar.stagedImages.length === 1, "testInputBar must have 1 staged image");
        assert(testInputBar.stagedImages[0] === "/tmp/test_image.png", "staged image path must match");
        testInputBar.unstageImage(0);
        assert(testInputBar.stagedImages.length === 0, "testInputBar must clear staged image on unstage");

        assert(/requestOpenImagePicker/.test(inputBarSrc), "ChatInputBar must declare requestOpenImagePicker signal");
        assert(/imagePickerVisible/.test(drawerSrc), "AssistantDrawer must declare imagePickerVisible state");
        assert(/LiquidGlassFilePicker/.test(drawerSrc), "AssistantDrawer must embed LiquidGlassFilePicker");
        assert(/pasteClipboardImage/.test(inputBarSrc), "ChatInputBar must implement clipboard paste helper");
        assert(/stagedStrip/.test(inputBarSrc), "ChatInputBar must declare stagedStrip thumbnail preview");

        // ToolConfirmationCard Image Read Detection
        assert(testImageCard.isImageRead === true, "ToolConfirmationCard must detect image read proposals");
        assert(testImageCard.detectedImagePath === "/tmp/sample_vision.png", "ToolConfirmationCard must extract image path");

        // 15. Mermaid Diagram Rendering Contract
        assert(testMermaidCard.mermaidSource.length > 0, "MermaidDiagramCard must bind mermaidSource");
        assert(testMermaidCard.diagramKind.length > 0, "MermaidDiagramCard must expose diagramKind");
        assert(testMermaidCard.showSource === false, "MermaidDiagramCard must default showSource to false");
        testMermaidCard.showSource = true;
        assert(testMermaidCard.showSource === true, "MermaidDiagramCard must support toggling showSource");
        testMermaidCard.showSource = false;

        const mermaidCardSrc = readLocalFile("../assistant/components/MermaidDiagramCard.qml");
        assert(mermaidCardSrc.length > 500, "MermaidDiagramCard.qml must be readable");
        assert(/renderDiagram/.test(mermaidCardSrc), "MermaidDiagramCard must implement renderDiagram");
        assert(/copyToClipboard/.test(mermaidCardSrc), "MermaidDiagramCard must support copying diagram/source to clipboard");

        const mermaidScript = readLocalFile("../scripts/render_mermaid.mjs");
        assert(mermaidScript.length > 500, "scripts/render_mermaid.mjs must exist");
        assert(/grok-mermaid/.test(mermaidScript), "render_mermaid.mjs must use grok-mermaid engine");

        // ChatView Mermaid integration
        assert(/MermaidDiagramCard/.test(chatViewSrc), "ChatView must instantiate MermaidDiagramCard for mermaid blocks");
        assert(/```mermaid/.test(chatViewSrc), "ChatView must detect mermaid code fences");

        // 16. Minimize to Taskbar / Dock Contract
        const headerSrc = readLocalFile("../assistant/components/AssistantHeader.qml");
        assert(/signal minimizeRequested/.test(headerSrc), "AssistantHeader must declare minimizeRequested signal");
        assert(/minimizeButton/.test(headerSrc), "AssistantHeader must provide minimizeButton");

        const configSrc = readLocalFile("../config/Config.qml");
        assert(/assistantMinimized/.test(configSrc), "Config must declare assistantMinimized property");
        assert(/function minimizeAssistant\(/.test(configSrc), "Config must implement minimizeAssistant");
        assert(/function restoreAssistant\(/.test(configSrc), "Config must implement restoreAssistant");
        assert(/function toggleAssistant\(/.test(configSrc), "Config must implement toggleAssistant");

        const dockSrc = readLocalFile("../shell/UnifiedDock.qml");
        assert(/copilotDockItem/.test(dockSrc), "UnifiedDock must declare copilotDockItem");
        assert(/Config\.assistantMinimized/.test(dockSrc), "UnifiedDock must react to assistantMinimized state");

        // Test Config minimize/restore state transitions
        assert(/function openAssistant\(/.test(configSrc), "Config must implement openAssistant");
        assert(/function closeAssistant\(/.test(configSrc), "Config must implement closeAssistant");

        if (typeof Config !== "undefined" && typeof Config.openAssistant === "function") {
            Config.openAssistant();
            assert(Config.assistantVisible === true, "assistantVisible must be true after openAssistant");
            assert(Config.assistantMinimized === false, "assistantMinimized must be false after openAssistant");

            Config.minimizeAssistant();
            assert(Config.assistantMinimized === true, "assistantMinimized must be true after minimizeAssistant");
            assert(Config.assistantVisible === false, "assistantVisible must be false when minimized");

            Config.restoreAssistant();
            assert(Config.assistantMinimized === false, "assistantMinimized must be false after restoreAssistant");
            assert(Config.assistantVisible === true, "assistantVisible must be true after restoreAssistant");

            Config.toggleAssistant();
            assert(Config.assistantVisible === false, "assistantVisible must be false after toggleAssistant when open");
            Config.closeAssistant();
        }

        // 17. Liquid Glass In-Process File Picker Contract
        const pickerSrc = readLocalFile("../assistant/components/LiquidGlassFilePicker.qml");
        assert(pickerSrc.length > 500, "LiquidGlassFilePicker.qml must be readable");
        assert(/FolderListModel/.test(pickerSrc), "LiquidGlassFilePicker must use FolderListModel for local file enumeration");
        assert(/quickPlaces/.test(pickerSrc), "LiquidGlassFilePicker must provide quick places sidebar navigation");
        assert(/searchQuery/.test(pickerSrc), "LiquidGlassFilePicker must support search query filtering");
        assert(/formatSize/.test(pickerSrc), "LiquidGlassFilePicker must implement human-readable formatSize helper");
        assert(/submitSelection/.test(pickerSrc), "LiquidGlassFilePicker must implement submitSelection function");
        assert(/dragTarget/.test(pickerSrc), "LiquidGlassFilePicker must accept dragTarget for window mobility");
        assert(/userDragged/.test(pickerSrc), "LiquidGlassFilePicker must emit userDragged signal on dragging header");
        assert(/dragTarget:\s*root\.isFloating/.test(drawerSrc), "AssistantDrawer must bind dragTarget to root");
        assert(drawer.imagePickerVisible === false, "AssistantDrawer imagePickerVisible must default to false");

        // 18. Native File Dialog & Any File Types Staging Contract
        assert(/FileDialog/.test(inputBarSrc), "ChatInputBar must declare FileDialog");
        assert(/modality:\s*Qt\.NonModal/.test(inputBarSrc), "FileDialog must be non-modal to prevent window input lock");
        assert(/All files \(\*\)/.test(inputBarSrc), "FileDialog must provide All files (*) filter");
        assert(typeof testInputBar.stageFile === "function", "ChatInputBar must implement stageFile");
        assert(typeof testInputBar.unstageFile === "function", "ChatInputBar must implement unstageFile");

        testInputBar.stageFile("/tmp/sample_code.rs");
        assert(testInputBar.stagedFiles.length === 1, "testInputBar must stage non-image file");
        assert(testInputBar.isImageFile("/tmp/sample_code.rs") === false, "isImageFile must be false for .rs file");
        assert(testInputBar.getFileExtension("/tmp/sample_code.rs") === "RS", "getFileExtension must return RS");
        assert(testInputBar.getFileName("/tmp/sample_code.rs") === "sample_code.rs", "getFileName must return filename");
        testInputBar.unstageFile(0);
        assert(testInputBar.stagedFiles.length === 0, "testInputBar must clear staged file on unstageFile");

        // 19. Session Persistence & Session Management Contract
        assert(/property var sessions/.test(serviceSrc), "AssistantService must declare sessions list");
        assert(/property string activeSessionId/.test(serviceSrc), "AssistantService must declare activeSessionId");
        assert(/property string activeSessionTitle/.test(serviceSrc), "AssistantService must declare activeSessionTitle");
        assert(/function loadActiveSession\(/.test(serviceSrc), "AssistantService must implement loadActiveSession");
        assert(/function refreshSessions\(/.test(serviceSrc), "AssistantService must implement refreshSessions");
        assert(/function loadSession\(/.test(serviceSrc), "AssistantService must implement loadSession");
        assert(/function createNewSession\(/.test(serviceSrc), "AssistantService must implement createNewSession");
        assert(/function deleteSession\(/.test(serviceSrc), "AssistantService must implement deleteSession");
        assert(/function persistActiveSession\(/.test(serviceSrc), "AssistantService must implement persistActiveSession");

        const sessionDrawerSrc = readLocalFile("../assistant/components/SessionListDrawer.qml");
        assert(sessionDrawerSrc.length > 500, "SessionListDrawer.qml must be readable");
        assert(/SessionListDrawer/.test(drawerSrc), "AssistantDrawer must embed SessionListDrawer");
        assert(!/root\.sessionSelected\([^)]*\);\s*root\.closed\(\)/.test(sessionDrawerSrc), "SessionListDrawer must NOT auto-close when selecting a session");
        assert(drawer.sessionsVisible === false, "AssistantDrawer sessionsVisible must default to false");
        assert(testSessionDrawer !== null, "SessionListDrawer must instantiate properly");

        // 20. Clean Liquid Glass Header Branding & Navigation
        assert(/signal sessionsRequested/.test(headerSrc), "AssistantHeader must declare sessionsRequested signal");
        assert(/signal newChatRequested/.test(headerSrc), "AssistantHeader must declare newChatRequested signal");
        assert(/iconName:\s*"auto_awesome"/.test(headerSrc), "AssistantHeader must use crisp auto_awesome icon");
        assert(!/Specular top hairline highlight/.test(headerSrc), "AssistantHeader must not have fake 1px highlight bar");

        // 21. E2E Header Action Buttons Clickability & Unblocked Drag Zone
        const hdr = floatingDrawer.headerItem;
        assert(hdr !== null && hdr !== undefined, "floatingDrawer must expose headerItem");
        assert(hdr.dragTarget === floatingDrawer, "headerItem dragTarget must bind to floatingDrawer");

        // Verify all action buttons have explicit z: 10 interactive priority
        assert(/id:\s*actionButtonsRow[\s\S]*?z:\s*10/.test(headerSrc), "AssistantHeader action buttons must reside in a z: 10 container above drag background");

        let newChatFired = false;
        hdr.newChatRequested.connect(function() { newChatFired = true; });
        hdr.newChatMouseItem.clicked(null);
        assert(newChatFired === true, "New Chat button must trigger newChatRequested and NOT be blocked by drag zone");

        let sessionsFired = false;
        hdr.sessionsRequested.connect(function() { sessionsFired = true; });
        hdr.sessionsMouseItem.clicked(null);
        assert(sessionsFired === true, "Sessions button must trigger sessionsRequested and NOT be blocked by drag zone");

        let minFired = false;
        hdr.minimizeRequested.connect(function() { minFired = true; });
        hdr.minMouseItem.clicked(null);
        assert(minFired === true, "Minimize button must trigger minimizeRequested and NOT be blocked by drag zone");

        let closeFired = false;
        hdr.closeRequested.connect(function() { closeFired = true; });
        hdr.closeMouseItem.clicked(null);
        assert(closeFired === true, "Close button must trigger closeRequested and NOT be blocked by drag zone");

        let initialHarness = hdr.testHarness;
        hdr.harnessMouseItem.clicked(null);
        assert(hdr.testHarness !== initialHarness, "Harness switcher pill must be clickable and toggle active engine");

        // 22. Non-Overlapping Sessions Sidebar Split View Contract
        assert(splitDrawer.sessionDrawerItem !== null, "splitDrawer must expose sessionDrawerItem");
        assert(splitDrawer.chatContentColumnItem !== null, "splitDrawer must expose chatContentColumnItem");
        assert(splitDrawer.sessionsVisible === true, "splitDrawer sessionsVisible must be true");
        assert(splitDrawer.sessionDrawerItem.width === 280, "sessionDrawerItem width must expand to 280px in split view");
        assert(splitDrawer.sessionDrawerItem.visible === true, "sessionDrawerItem must be visible");

        // Absolute zero-overlap split view guarantee:
        // Sidebar's right edge must be less than or equal to the chat content column's left edge
        const sidebarRightEdge = splitDrawer.sessionDrawerItem.x + splitDrawer.sessionDrawerItem.width;
        const chatColumnLeftEdge = splitDrawer.chatContentColumnItem.x;
        assert(sidebarRightEdge <= chatColumnLeftEdge, "Sessions sidebar must NOT overlap chat content (sidebar right edge " + sidebarRightEdge + " <= chat column left edge " + chatColumnLeftEdge + ")");
        assert(splitDrawer.chatContentColumnItem.width >= 400, "Chat content column must maintain full reading width in split view");
        assert(splitDrawer.width >= splitDrawer.baseDefaultWidth + 200, "Floating window width must expand to accommodate sidebar without squeezing messages");

        // Dynamic toggle check
        floatingDrawer.customWidth = 0;
        floatingDrawer.customHeight = 0;
        floatingDrawer.sessionsVisible = false;
        assert(floatingDrawer.sessionsVisible === false, "floatingDrawer sessionsVisible must start false");
        floatingDrawer.sessionsVisible = true;
        assert(floatingDrawer.sessionsVisible === true, "floatingDrawer sessionsVisible must toggle to true");

        // Selecting a session must NOT close the sessions sidebar
        let sessionSelectedFired = false;
        floatingDrawer.sessionDrawerItem.sessionSelected.connect(function(id) {
            sessionSelectedFired = true;
        });
        let closedFired = false;
        floatingDrawer.sessionDrawerItem.closed.connect(function() {
            closedFired = true;
        });

        floatingDrawer.sessionDrawerItem.sessionSelected("session_test_persist");
        assert(sessionSelectedFired === true, "sessionSelected signal must fire on selection");
        assert(closedFired === false, "Selecting a session must NOT fire closed signal");
        assert(floatingDrawer.sessionsVisible === true, "sessionsVisible must remain true when a session is selected");

        floatingDrawer.sessionsVisible = false;

        // 23. File Explorer Sort Criteria, Direction, and View Size Modes Contract
        assert(testPicker.sortField !== undefined, "LiquidGlassFilePicker must expose sortField");
        assert(testPicker.sortReversed !== undefined, "LiquidGlassFilePicker must expose sortReversed");
        assert(testPicker.viewMode !== undefined, "LiquidGlassFilePicker must expose viewMode");
        assert(testPicker.filterCategory !== undefined, "LiquidGlassFilePicker must expose filterCategory");

        // Default state
        assert(testPicker.sortField === FolderListModel.Name, "Default sortField must be FolderListModel.Name");
        assert(testPicker.sortReversed === false, "Default sortReversed must be false (Ascending)");
        assert(testPicker.viewMode === "grid_medium", "Default viewMode must be grid_medium");
        assert(testPicker.filterCategory === 0, "Default filterCategory must be 0 (All Files)");

        // Sort field switching
        testPicker.sortField = FolderListModel.Time;
        assert(testPicker.sortField === FolderListModel.Time, "sortField must support switching to Date Modified (Time)");
        testPicker.sortField = FolderListModel.Size;
        assert(testPicker.sortField === FolderListModel.Size, "sortField must support switching to File Size");

        // Sort reverse toggle
        testPicker.sortReversed = true;
        assert(testPicker.sortReversed === true, "sortReversed must support descending order");
        testPicker.sortReversed = false;
        assert(testPicker.sortReversed === false, "sortReversed must support ascending order");

        // View mode switching (Small, Medium, Large Grid, Detailed List)
        testPicker.viewMode = "grid_small";
        assert(testPicker.viewMode === "grid_small", "viewMode must support grid_small");
        testPicker.viewMode = "grid_large";
        assert(testPicker.viewMode === "grid_large", "viewMode must support grid_large");
        testPicker.viewMode = "list";
        assert(testPicker.viewMode === "list", "viewMode must support list view");

        // Filter category switching (All Files, Images, Code, Docs)
        testPicker.filterCategory = 1;
        assert(testPicker.filterCategory === 1, "filterCategory must switch to Images");
        testPicker.filterCategory = 2;
        assert(testPicker.filterCategory === 2, "filterCategory must switch to Code");
        testPicker.filterCategory = 0;
        assert(testPicker.filterCategory === 0, "filterCategory must switch back to All Files");

        // 24. Multi-Crash Alert Banner, Carousel Navigation & Dismissal Contract
        assert(floatingDrawer.crashBannerItem !== null, "floatingDrawer must expose crashBannerItem");
        const banner = floatingDrawer.crashBannerItem;
        assert(banner.currentCrashIndex !== undefined, "crashBannerItem must expose currentCrashIndex");
        assert(banner.safeIndex !== undefined, "crashBannerItem must expose safeIndex");
        assert(banner.prevMouseItem !== undefined, "crashBannerItem must expose prevMouseItem");
        assert(banner.nextMouseItem !== undefined, "crashBannerItem must expose nextMouseItem");
        assert(banner.debugMouseItem !== undefined, "crashBannerItem must expose debugMouseItem");
        assert(banner.dismissMouseItem !== undefined, "crashBannerItem must expose dismissMouseItem");

        // Verify carousel indexing math & bounds clamping
        banner.currentCrashIndex = 0;
        assert(banner.safeIndex === 0, "safeIndex must be 0 when currentCrashIndex is 0");
        banner.currentCrashIndex = 5;
        assert(banner.safeIndex <= Math.max(0, banner.crashCount - 1), "safeIndex must clamp to crashCount - 1");

        // Verify source contract for multi-crash carousel controls & dismiss
        const assistantDrawerSrc = readLocalFile("../assistant/AssistantDrawer.qml");
        assert(/chevron_left/.test(assistantDrawerSrc), "AssistantDrawer must include previous crash chevron");
        assert(/chevron_right/.test(assistantDrawerSrc), "AssistantDrawer must include next crash chevron");
        assert(/dismissMouse/.test(assistantDrawerSrc), "AssistantDrawer must include dismiss button");
        assert(/activeCrashes/.test(assistantDrawerSrc), "AssistantDrawer must bind to AssistantService.activeCrashes");

        // 13. Liquid Glass Design System & Component Polishing Contract
        // Verify AssistantDrawer crashBanner liquid glass styling
        assert(/dbgMouse\.pressed\s*\?\s*0\.94/.test(assistantDrawerSrc), "crashBanner Debug button must have spring scale micro-physics");
        assert(/Qt\.alpha\(Colors\.m3error,\s*0\.20\)/.test(assistantDrawerSrc), "crashBanner Debug button must use liquid glass translucent fill");

        // Verify SessionListDrawer + New button and action buttons
        const sessionSrc = readLocalFile("../assistant/components/SessionListDrawer.qml");
        assert(/radius:\s*14/.test(sessionSrc), "SessionListDrawer + New button must be a stadium pill (radius 14)");
        assert(/newChatMouse\.pressed\s*\?\s*0\.95/.test(sessionSrc), "SessionListDrawer + New button must have spring scale micro-physics");
        assert(/delMouse\.pressed\s*\?\s*0\.90/.test(sessionSrc), "SessionListDrawer delete button must have spring scale micro-physics");
        assert(/closeMouse\.pressed\s*\?\s*0\.90/.test(sessionSrc), "SessionListDrawer close button must have spring scale micro-physics");

        // Verify ChatInputBar liquid glass buttons & spring micro-physics
        const chatInputSrc = readLocalFile("../assistant/components/ChatInputBar.qml");
        assert(/sendMouse\.pressed\s*\?\s*0\.94/.test(chatInputSrc), "ChatInputBar send button must have spring scale micro-physics");
        assert(/attachMouse\.pressed\s*\?\s*0\.94/.test(chatInputSrc), "ChatInputBar attach button must have spring scale micro-physics");
        assert(/Qt\.alpha\(Colors\.primary,\s*0\.18\)/.test(chatInputSrc), "ChatInputBar send button must use liquid glass primary fill");

        // Verify ToolConfirmationCard liquid glass buttons
        const toolCardSrc = readLocalFile("../assistant/components/ToolConfirmationCard.qml");
        assert(/approveMouse\.pressed\s*\?\s*0\.94/.test(toolCardSrc), "ToolConfirmationCard approve button must have spring scale micro-physics");
        assert(/denyMouse\.pressed\s*\?\s*0\.94/.test(toolCardSrc), "ToolConfirmationCard deny button must have spring scale micro-physics");

        // Verify LiquidGlassFilePicker Attach button & checkboxes (zero hardcoded #12131A)
        const filePickerSrc = readLocalFile("../assistant/components/LiquidGlassFilePicker.qml");
        assert(!/#12131A/i.test(filePickerSrc), "LiquidGlassFilePicker must NOT contain hardcoded #12131A text/colors");
        assert(/attachMouse\.pressed\s*\?\s*0\.94/.test(filePickerSrc), "LiquidGlassFilePicker attach button must have spring scale micro-physics");

        // Verify ModelProviderBar frosted glass dropdowns & spring micro-physics
        const modelBarSrc = readLocalFile("../assistant/components/ModelProviderBar.qml");
        assert(/providerHover\.pressed\s*\?\s*0\.96/.test(modelBarSrc), "ModelProviderBar provider button must have spring scale micro-physics");
        assert(/modelHover\.pressed\s*\?\s*0\.96/.test(modelBarSrc), "ModelProviderBar model button must have spring scale micro-physics");
        assert(/0\.90/.test(modelBarSrc), "ModelProviderBar dropdown popups must use frosted glass (0.90 alpha)");

        // Verify AssistantHeader action buttons spring micro-physics
        const asstHdrSrc = readLocalFile("../assistant/components/AssistantHeader.qml");
        assert(/newChatMouse\.pressed\s*\?\s*0\.92/.test(asstHdrSrc), "AssistantHeader newChat button must have spring scale micro-physics");
        assert(/closeMouse\.pressed\s*\?\s*0\.92/.test(asstHdrSrc), "AssistantHeader close button must have spring scale micro-physics");

        // 25. Chat Content Typography & Markdown Headings Normalization Contract
        assert(floatingDrawer.chatViewItem !== null, "floatingDrawer must expose chatViewItem");
        const cv = floatingDrawer.chatViewItem;
        assert(typeof cv.normalizeMarkdown === "function", "ChatView must expose normalizeMarkdown function");

        // Verify ATX heading normalization: H1 -> ## (~19.5px Bold, Theme.fontTitleMedium)
        assert(cv.normalizeMarkdown("# Final campaign") === "## Final campaign", "H1 must normalize to ## (19.5px Bold)");
        assert(cv.normalizeMarkdown("Text\n\n# Heading 1") === "Text\n\n## Heading 1", "H1 after paragraph must normalize to ##");
        assert(cv.normalizeMarkdown("Text\n# Heading 1") === "Text\n\n## Heading 1", "H1 preceded by single newline must insert blank line for proper top margin");
        assert(cv.normalizeMarkdown("# Heading With Trailing Hashes ####") === "## Heading With Trailing Hashes", "ATX heading trailing hashes must be stripped");

        // Verify H2 through H6 distinct hierarchy normalization
        assert(cv.normalizeMarkdown("## Sub-section Analysis") === "### Sub-section Analysis", "H2 must normalize to ### (15.2px DemiBold)");
        assert(cv.normalizeMarkdown("### Repro Script") === "#### Repro Script", "H3 must normalize to #### (13.0px Bold)");
        assert(cv.normalizeMarkdown("#### Step Details") === "#### *Step Details*", "H4 must normalize to #### *Step Details* (13.0px Bold-Italic)");
        assert(cv.normalizeMarkdown("#### *Already Italic*") === "#### *Already Italic*", "H4 already italic must not double-wrap");
        assert(cv.normalizeMarkdown("##### Minor Note") === "##### Minor Note", "H5 must normalize to ##### (10.8px Bold)");
        assert(cv.normalizeMarkdown("###### Sub-note") === "###### Sub-note", "H6 must normalize to ###### (8.7px Bold)");

        // Verify Setext heading normalization
        assert(cv.normalizeMarkdown("Setext Title\n=====") === "## Setext Title", "Setext H1 must normalize to ##");
        assert(cv.normalizeMarkdown("Setext Subtitle\n-----") === "### Setext Subtitle", "Setext H2 must normalize to ###");
        assert(cv.normalizeMarkdown("Text\nSetext Title\n=====") === "Text\n\n## Setext Title", "Setext H1 preceded by text must insert blank line");

        // Verify Fenced Code Block preservation (bash/python comments with # must NEVER be altered)
        const codeBlockInput = "# Main Title\n```bash\n# this is a bash comment\nkill -9 1234\n```\n# Next Title";
        const codeBlockExpected = "## Main Title\n```bash\n# this is a bash comment\nkill -9 1234\n```\n## Next Title";
        assert(cv.normalizeMarkdown(codeBlockInput) === codeBlockExpected, "Fenced code blocks must be preserved byte-for-byte without altering internal comments");

        const tildeCodeBlock = "~~~python\n# python comment\nx = 42\n~~~\n# Final Heading";
        const tildeExpected = "~~~python\n# python comment\nx = 42\n~~~\n## Final Heading";
        assert(cv.normalizeMarkdown(tildeCodeBlock) === tildeExpected, "Tilde code blocks must also be preserved byte-for-byte");

        // Verify Edge Cases
        assert(cv.normalizeMarkdown("") === "", "Empty string must return empty string");
        assert(cv.normalizeMarkdown(null) === "", "Null must return empty string");
        assert(cv.normalizeMarkdown("Plain text #hashtag #ffffff") === "Plain text #hashtag #ffffff", "Hashtags and hex colors must not be modified");

        // Verify ChatView source contracts for font tokens and tool textFormat
        assert(/normalizeMarkdown\(modelData\.text/.test(chatViewSrc), "ChatView must bind bubbleText through normalizeMarkdown");
        assert(/Theme\.fontBodySmall/.test(chatViewSrc), "ChatView must use Theme.fontBodySmall (13px) for bubbleText font size");
        assert(/isTool\s*\?\s*Text\.PlainText\s*:\s*Text\.MarkdownText/.test(chatViewSrc), "ChatView must render tool output as PlainText");

        console.log("PASS: All Assistant Drawer tests passed!");
        Qt.exit(0);
    }
}
