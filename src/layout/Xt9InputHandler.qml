import QtQuick 2.0
import com.meego.maliitquick 1.0
import com.jolla.xt9 1.0
import Sailfish.Silica 1.0
import com.jolla.keyboard 1.0

InputHandler {
    id: xt9Handler

    property int candidateSpaceIndex: -1
    property string preedit

    // hack: currently possible to know if there's active focus only on signal handler.
    // workaround with this to avoid predictions changing while hiding keyboard
    property bool trackSurroundings

    Xt9EngineThread {
        id: thread
        // note: also china language codes being set with this, assume xt9 model just ignores such
        language: layoutRow.layout ? layoutRow.layout.languageCode : ""

        property int shiftState: keyboard.isShifted ? (keyboard.isShiftLocked ? Xt9Model.ShiftLocked
                                                                              : Xt9Model.ShiftLatched)
                                                    : Xt9Model.NoShift
        onShiftStateChanged: setShiftState(shiftState)

        function abort(word) {
            var oldPreedit = xt9Handler.preedit
            xt9Handler.commit(word)
            xt9Handler.preedit = oldPreedit.substr(word.length, oldPreedit.length-word.length)
            if (xt9Handler.preedit !== "") {
                MInputMethodQuick.sendPreedit(xt9Handler.preedit)
            }
        }
    }

    Component {
        id: pasteComponent
        PasteButton {
            onClicked: {
                xt9Handler.commit(xt9Handler.preedit)
                MInputMethodQuick.sendCommit(Clipboard.text)
                keyboard.expandedPaste = false
            }
        }
    }

    topItem: Component {
        TopItem {
            SilicaListView {
                id: predictionList

                model: thread.engine
                orientation: ListView.Horizontal
                anchors.fill: parent
                header: pasteComponent
                boundsBehavior: !keyboard.expandedPaste && Clipboard.hasText ? Flickable.DragOverBounds : Flickable.StopAtBounds

                onDraggingChanged: {
                    if (!dragging && !keyboard.expandedPaste && contentX < -(headerItem.width + Theme.paddingLarge)) {
                        keyboard.expandedPaste = true
                        positionViewAtBeginning()
                    }
                }

                delegate: BackgroundItem {
                    onClicked: applyPrediction(model.text, model.index)
                    width: candidateText.width + Theme.paddingLarge * 2
                    height: parent ? parent.height : 0

                    Text {
                        id: candidateText
                        anchors.centerIn: parent
                        color: highlighted ? Theme.highlightColor : Theme.primaryColor
                        font { pixelSize: Theme.fontSizeSmall; family: Theme.fontFamily }
                        text: formatText(model.text)

                        function formatText(text) {
                            if (text === undefined)
                                return ""
                            var preeditLength = xt9Handler.preedit.length
                            if (text.substr(0, preeditLength) === xt9Handler.preedit) {
                                return "<font color=\"" + Theme.highlightColor + "\">" + xt9Handler.preedit + "</font>"
                                        + text.substr(preeditLength)
                            } else {
                                return text
                            }
                        }
                    }
                }

                Connections {
                    target: thread.engine
                    onPredictionsChanged: {
                        predictionList.positionViewAtBeginning()
                    }
                }

                Connections {
                    target: Clipboard
                    onTextChanged: {
                        if (Clipboard.hasText) {
                            // need to have updated width before repositioning view
                            positionerTimer.restart()
                        }
                    }
                }

                Timer {
                    id: positionerTimer
                    interval: 8
                    onTriggered: predictionList.positionViewAtBeginning()
                }
            }
        }
    }

    onActiveChanged: {
        if (!active && preedit !== "") {
            thread.acceptWord(preedit, false)
            commit(preedit)
        }

        updateButtons()
    }

    Connections {
        target: keyboard
        onFullyOpenChanged: {
            // TODO: could avoid if new keyboard is just the same as the previous one
            updateButtons()
        }
        onLayoutChanged: updateButtons()
    }

    Connections {
        target: MInputMethodQuick
        onFocusTargetChanged: {
            xt9Handler.trackSurroundings = activeEditor
        }

        onEditorStateUpdate: {
            if (!xt9Handler.trackSurroundings) {
                return
            }

            if (MInputMethodQuick.surroundingTextValid) {
                var text = MInputMethodQuick.surroundingText.substring(0, MInputMethodQuick.cursorPosition)
                thread.setContext(text)
            } else {
                thread.setContext("")
            }
        }
    }

    function updateButtons() {
        // QtQuick positions Columns and Rows on next frame. avoid wrong positions by running only when fully shown.
        if (!active || !keyboard.fullyOpen) {
            return
        }

        var layout = keyboard.layout

        var children = layout.children
        var i
        var child

        thread.startLayout(layout.width, layout.height)

        for (i = 0; i < children.length; ++i) {
            addButtonsFromChildren(children[i], layout)
        }

        thread.finishLayout()
    }

    function addButtonsFromChildren(item, layout) {
        var children = item.children
        var child

        for (var i = 0; i < children.length; ++i) {
            child = children[i]
            if (typeof child.keyType !== 'undefined') {
                if (child.keyType === KeyType.CharacterKey) {
                    var mapped = item.mapToItem(layout, child.x, child.y, child.width, child.height)
                    var buttonText = child.text + child.nativeAccents
                    var buttonTextShifted = child.captionShifted + child.nativeAccentsShifted

                    thread.addLayoutButton(mapped.x, mapped.y, mapped. width, mapped.height, buttonText, buttonTextShifted)
                }
            } else {
                addButtonsFromChildren(child, layout)
            }
        }
    }

    function applyPrediction(replacement, index) {
        console.log("candidate clicked: " + replacement + "\n")
        replacement = replacement + " "
        candidateSpaceIndex = MInputMethodQuick.surroundingTextValid
                ? MInputMethodQuick.cursorPosition + replacement.length : -1
        commit(replacement)
        thread.acceptPrediction(index)
    }

    function handleKeyClick() {
        var handled = false
        keyboard.expandedPaste = false

        if (pressedKey.key === Qt.Key_Space) {
            if (preedit !== "") {
                thread.acceptWord(preedit, true)
                commit(preedit + " ")
                keyboard.autocaps = false // assuming no autocaps after input with xt9 preedit
            } else {
                commit(" ")
            }

            if (keyboard.shiftState !== ShiftState.LockedShift) {
                keyboard.shiftState = ShiftState.AutoShift
            }

            handled = true

        } else if (pressedKey.key === Qt.Key_Return) {
            if (preedit !== "") {
                thread.acceptWord(preedit, false)
                commit(preedit)
            }
            if (keyboard.shiftState !== ShiftState.LockedShift) {
                keyboard.shiftState = ShiftState.AutoShift
            }

        } else if (pressedKey.key === Qt.Key_Backspace && preedit !== "") {
            preedit = preedit.substr(0, preedit.length-1)
            thread.processBackspace()
            MInputMethodQuick.sendPreedit(preedit)

            if (keyboard.shiftState !== ShiftState.LockedShift) {
                if (preedit.length === 0) {
                    keyboard.shiftState = ShiftState.AutoShift
                } else {
                    keyboard.shiftState = ShiftState.NoShift
                }
            }

            handled = true

        } else if (pressedKey.text.length !== 0) {
            var wordSymbol = "\'-".indexOf(pressedKey.text) >= 0

            if (thread.isLetter(pressedKey.text) || wordSymbol) {
                var forceAdd = pressedKey.keyType === KeyType.PopupKey
                        || keyboard.inSymView
                        || keyboard.inSymView2
                        || wordSymbol

                thread.processSymbol(pressedKey.text, forceAdd)
                preedit += pressedKey.text

                if (keyboard.shiftState !== ShiftState.LockedShift) {
                    keyboard.shiftState = ShiftState.NoShift
                }

                MInputMethodQuick.sendPreedit(preedit)
                handled = true
            } else {
                // normal symbols etc.
                if (preedit !== "") {
                    thread.acceptWord(preedit, false) // do we need to notify xt9 with the appended symbol?
                    commit(preedit + pressedKey.text)
                } else {
                    if (candidateSpaceIndex > 0 && candidateSpaceIndex === MInputMethodQuick.cursorPosition
                            && ",.?!".indexOf(pressedKey.text) >= 0
                            && MInputMethodQuick.surroundingText.charAt(MInputMethodQuick.cursorPosition - 1) === " ") {
                        if (thread.language === "FR" && "?!".indexOf(pressedKey.text) >= 0) {
                            // follow French grammar rules for ? and !
                            MInputMethodQuick.sendCommit(pressedKey.text + " ")
                        } else {
                            // replace automatically added space from candidate clicking
                            MInputMethodQuick.sendCommit(pressedKey.text + " ", -1, 1)
                        }
                        preedit = ""
                    } else {
                        commit(pressedKey.text)
                    }
                }

                handled = true
            }
        } else if (pressedKey.key === Qt.Key_Backspace && MInputMethodQuick.surroundingTextValid
                   && !MInputMethodQuick.hasSelection
                   && MInputMethodQuick.cursorPosition >= 2
                   && isInputCharacter(MInputMethodQuick.surroundingText.charAt(MInputMethodQuick.cursorPosition - 2))) {
            // backspacing into a word, re-activate it
            var length = 1
            var pos = MInputMethodQuick.cursorPosition - 3
            for (; pos >= 0 && isInputCharacter(MInputMethodQuick.surroundingText.charAt(pos)); --pos) {
                length++
            }
            pos++

            var word = MInputMethodQuick.surroundingText.substring(pos, pos + length)
            MInputMethodQuick.sendKey(Qt.Key_Backspace, 0, "\b", Maliit.KeyClick)
            MInputMethodQuick.sendPreedit(word, undefined, -length, length)
            thread.reactivateWord(word)
            preedit = word
            handled = true
        }

        if (pressedKey.keyType !== KeyType.ShiftKey && pressedKey.keyType !== KeyType.SymbolKey) {
            candidateSpaceIndex = -1
        }

        return handled
    }

    function isInputCharacter(character) {
        return thread.isLetter(character) || "\'-".indexOf(character) >= 0
    }

    function reset() {
        thread.reset()
        preedit = ""
    }

    function commit(text) {
        MInputMethodQuick.sendCommit(text)
        preedit = ""
    }
}
