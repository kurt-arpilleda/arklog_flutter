import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

class TodoDialog extends StatefulWidget {
  final String currentIdNumber;
  final String currentLanguage;
  final Function updateTodoCount;

  const TodoDialog({
    Key? key,
    required this.currentIdNumber,
    required this.currentLanguage,
    required this.updateTodoCount,
  }) : super(key: key);

  @override
  _TodoDialogState createState() => _TodoDialogState();
}

class _TodoDialogState extends State<TodoDialog> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _todos = [];
  List<Map<String, dynamic>> _softwareLinks = [];
  bool _isLoading = true;
  bool _isDeleteMode = false;
  bool _isEditMode = false;
  Set<int> _selectedTodos = Set<int>();
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _fetchTodos(),
      _fetchSoftwareLinks(),
    ]);
  }

  Future<void> _fetchTodos() async {
    try {
      final todoData = await _apiService.fetchTodos(widget.currentIdNumber);
      setState(() {
        _todos = List<Map<String, dynamic>>.from(todoData['todos'] ?? []);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.currentLanguage == 'ja'
                ? 'タスクの読み込みエラー'
                : 'Error loading tasks',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchSoftwareLinks() async {
    try {
      final softwareData = await _apiService.fetchSoftwareLinks();
      setState(() {
        _softwareLinks = softwareData;
      });
    } catch (e) {
      print('Error loading software links: $e');
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, HH:mm').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  Future<void> _updateTodoStatus(int todoId, int status) async {
    try {
      await _apiService.updateTodo(todoId, status);
      setState(() {
        final todoIndex = _todos.indexWhere((todo) => todo['todoId'] == todoId);
        if (todoIndex != -1) {
          _todos[todoIndex]['done'] = status;
        }
      });
      await widget.updateTodoCount();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.currentLanguage == 'ja'
                ? 'タスクが更新されました'
                : 'Task updated successfully',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.currentLanguage == 'ja'
                ? 'エラーが発生しました'
                : 'Error updating task',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _editTodo(int todoId, String currentTask, String currentAppToOpen) async {
    final TextEditingController taskController = TextEditingController(text: currentTask);
    String selectedApp = currentAppToOpen;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text(
                widget.currentLanguage == 'ja' ? 'タスクを編集' : 'Edit Task',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3452B4),
                ),
              ),
              content: IntrinsicHeight(
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: taskController,
                        decoration: InputDecoration(
                          labelText: widget.currentLanguage == 'ja' ? 'タスクを編集' : 'Edit task',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return widget.currentLanguage == 'ja'
                                ? 'タスクを入力してください'
                                : 'Please enter a task';
                          }
                          return null;
                        },
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                      ),
                      SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedApp.isEmpty ? null : selectedApp,
                        decoration: InputDecoration(
                          labelText: widget.currentLanguage == 'ja' ? 'アプリを選択' : 'Select Application',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String>(
                            value: null,
                            child: Text(
                              widget.currentLanguage == 'ja' ? 'なし' : 'None',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          ..._softwareLinks.map((software) {
                            return DropdownMenuItem<String>(
                              value: software['linkID'].toString(),
                              child: Text(software['softwareName']),
                            );
                          }).toList(),
                        ],
                        onChanged: (String? newValue) {
                          setModalState(() {
                            selectedApp = newValue ?? '';
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    widget.currentLanguage == 'ja' ? 'キャンセル' : 'Cancel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF3452B4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    widget.currentLanguage == 'ja' ? '保存' : 'SAVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      try {
        await _apiService.editTodo(todoId, taskController.text.trim(), selectedApp);
        await _fetchTodos();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.currentLanguage == 'ja'
                  ? 'タスクが更新されました'
                  : 'Task updated successfully',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.currentLanguage == 'ja'
                  ? 'タスクの更新に失敗しました'
                  : 'Failed to update task',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _showAddTodoDialog() async {
    final TextEditingController taskController = TextEditingController();
    String selectedApp = '';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text(
                widget.currentLanguage == 'ja' ? 'タスクを追加' : 'Add Task',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3452B4),
                ),
              ),
              content: IntrinsicHeight(
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: taskController,
                        decoration: InputDecoration(
                          labelText: widget.currentLanguage == 'ja' ? 'タスクを入力' : 'Enter task',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return widget.currentLanguage == 'ja'
                                ? 'タスクを入力してください'
                                : 'Please enter a task';
                          }
                          return null;
                        },
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                      ),
                      SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: widget.currentLanguage == 'ja' ? 'アプリを選択' : 'Select Application',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String>(
                            value: '',
                            child: Text(
                              widget.currentLanguage == 'ja' ? 'なし' : 'None',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          ..._softwareLinks.map((software) {
                            return DropdownMenuItem<String>(
                              value: software['linkID'].toString(),
                              child: Text(software['softwareName']),
                            );
                          }).toList(),
                        ],
                        onChanged: (String? newValue) {
                          setModalState(() {
                            selectedApp = newValue ?? '';
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    widget.currentLanguage == 'ja' ? 'キャンセル' : 'Cancel',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop();
                      _addNewTodo(taskController.text.trim(), selectedApp);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF3452B4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    widget.currentLanguage == 'ja' ? '追加' : 'ADD',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addNewTodo(String task, String appToOpen) async {
    try {
      await _apiService.addTodo(widget.currentIdNumber, task, appToOpen);
      await _fetchTodos();
      await widget.updateTodoCount();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.currentLanguage == 'ja'
                ? 'タスクが追加されました'
                : 'Task added successfully',
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.currentLanguage == 'ja'
                ? 'タスクの追加に失敗しました'
                : 'Failed to add task',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleDeleteMode() {
    setState(() {
      _isDeleteMode = !_isDeleteMode;
      _isEditMode = false;
      _selectedTodos.clear();
      _selectAll = false;
    });
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      _isDeleteMode = false;
      _selectedTodos.clear();
      _selectAll = false;
    });
  }

  void _toggleTodoSelection(int todoId) {
    setState(() {
      if (_selectedTodos.contains(todoId)) {
        _selectedTodos.remove(todoId);
      } else {
        _selectedTodos.add(todoId);
      }
      _selectAll = _selectedTodos.length == _todos.length;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectAll) {
        _selectedTodos.clear();
      } else {
        _selectedTodos = Set<int>.from(_todos.map((todo) => todo['todoId'] as int));
      }
      _selectAll = !_selectAll;
    });
  }

  Future<void> _deleteSelectedTodos() async {
    if (_selectedTodos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            widget.currentLanguage == 'ja' ? '確認' : 'Confirm',
            style: TextStyle(color: Colors.red),
          ),
          content: Text(
            widget.currentLanguage == 'ja'
                ? '${_selectedTodos.length}件のタスクを削除しますか？'
                : 'Delete ${_selectedTodos.length} task(s)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(widget.currentLanguage == 'ja' ? 'キャンセル' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(widget.currentLanguage == 'ja' ? '削除' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteTodos(_selectedTodos.toList());
        await _fetchTodos();
        await widget.updateTodoCount();
        _toggleDeleteMode();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.currentLanguage == 'ja'
                  ? 'タスクを削除しました'
                  : 'Tasks deleted successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.currentLanguage == 'ja'
                  ? '削除に失敗しました'
                  : 'Failed to delete tasks',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3452B4), Color(0xFF2053B3)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.task_alt,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.currentLanguage == 'ja' ? 'やることリスト' : 'To-Do List',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_todos.length} ${widget.currentLanguage == 'ja' ? '件のタスク' : 'tasks'}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isDeleteMode || _isEditMode)
                    IconButton(
                      onPressed: () {
                        if (_isDeleteMode) _toggleDeleteMode();
                        if (_isEditMode) _toggleEditMode();
                      },
                      icon: Icon(Icons.close, color: Colors.white),
                      tooltip: widget.currentLanguage == 'ja' ? 'キャンセル' : 'Cancel',
                    )
                  else
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: Colors.white),
                    ),
                ],
              ),
            ),
            if (_isDeleteMode && _todos.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectAll,
                      onChanged: (bool? value) {
                        _toggleSelectAll();
                      },
                    ),
                    Text(
                      widget.currentLanguage == 'ja' ? 'すべて選択' : 'Select All',
                      style: TextStyle(fontSize: 14),
                    ),
                    Spacer(),
                    Text(
                      '${_selectedTodos.length} ${widget.currentLanguage == 'ja' ? '件選択中' : 'selected'}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            _isLoading
                ? Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
                : Flexible(
              child: _todos.isEmpty
                  ? Container(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.task_alt,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 16),
                    Text(
                      widget.currentLanguage == 'ja'
                          ? 'タスクはありません'
                          : 'No tasks available',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: Text(
                        widget.currentLanguage == 'ja'
                            ? '「＋」ボタンを押して、やることリストにタスクを追加しましょう。'
                            : 'Click the + button to add a task to your to-do list.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.all(16),
                itemCount: _todos.length,
                itemBuilder: (context, index) {
                  final todo = _todos[index];
                  final isCompleted = todo['done'] == 1;
                  final isSelected = _selectedTodos.contains(todo['todoId']);
                  final softwareName = todo['softwareName'] ?? '';
                  final appToOpen = todo['appToOpen']?.toString() ?? '';

                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (_isDeleteMode ? Colors.red.shade100 : Colors.blue.shade100)
                          : isCompleted
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? (_isDeleteMode ? Colors.red : Colors.blue)
                            : isCompleted
                            ? Colors.green.shade200
                            : Colors.blue.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: _isDeleteMode || _isEditMode
                          ? Checkbox(
                        value: isSelected,
                        onChanged: (bool? value) {
                          _toggleTodoSelection(todo['todoId']);
                        },
                        activeColor: _isDeleteMode ? Colors.red : Colors.blue,
                      )
                          : Container(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: isCompleted,
                          onChanged: (bool? value) {
                            if (value != null) {
                              _updateTodoStatus(
                                todo['todoId'],
                                value ? 1 : 0,
                              );
                            }
                          },
                          activeColor: Colors.green,
                        ),
                      ),
                      title: Text(
                        todo['task'] ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: isCompleted
                              ? Colors.grey[600]
                              : Colors.grey[800],
                        ),
                      ),
                      subtitle: Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (softwareName.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.apps,
                                      size: 14,
                                      color: Colors.blue[600],
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      softwareName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey[500],
                                ),
                                SizedBox(width: 4),
                                Text(
                                  _formatDateTime(todo['stamp']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                Spacer(),
                                if (!_isDeleteMode && !_isEditMode)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCompleted
                                          ? Colors.green
                                          : Colors.orange,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      isCompleted
                                          ? (widget.currentLanguage == 'ja' ? '完了' : 'Done')
                                          : (widget.currentLanguage == 'ja' ? '進行中' : 'Ongoing'),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      onTap: () {
                        if (_isEditMode && _selectedTodos.isEmpty) {
                          _editTodo(todo['todoId'], todo['task'] ?? '', appToOpen);
                        } else if (_isDeleteMode || _isEditMode) {
                          _toggleTodoSelection(todo['todoId']);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_isEditMode || _isDeleteMode)
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            if (_isDeleteMode) _toggleDeleteMode();
                            if (_isEditMode) _toggleEditMode();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            widget.currentLanguage == 'ja' ? 'キャンセル' : 'CANCEL',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isDeleteMode
                              ? _deleteSelectedTodos
                              : () {
                            if (_selectedTodos.isNotEmpty) {
                              final todoId = _selectedTodos.first;
                              final todo = _todos.firstWhere((t) => t['todoId'] == todoId);
                              final appToOpen = todo['appToOpen']?.toString() ?? '';
                              _editTodo(todoId, todo['task'] ?? '', appToOpen);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isDeleteMode ? Colors.red : Colors.blue,
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _isDeleteMode
                                ? (widget.currentLanguage == 'ja' ? '削除' : 'DELETE')
                                : (widget.currentLanguage == 'ja' ? '編集' : 'EDIT'),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Color(0xFF3452B4),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onPressed: _toggleEditMode,
                            icon: Icon(Icons.edit, color: Colors.white),
                            tooltip: widget.currentLanguage == 'ja' ? '編集' : 'Edit',
                          ),
                        ),
                        SizedBox(width: 6),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onPressed: _toggleDeleteMode,
                            icon: Icon(Icons.delete, color: Colors.white),
                            tooltip: widget.currentLanguage == 'ja' ? '削除' : 'Delete',
                          ),
                        ),
                      ],
                    ),
                  FloatingActionButton(
                    onPressed: () => _showAddTodoDialog(),
                    backgroundColor: Color(0xFF3452B4),
                    mini: true,
                    child: Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}