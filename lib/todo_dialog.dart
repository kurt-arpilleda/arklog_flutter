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
  bool _isLoading = true;
  bool _isDeleteMode = false;
  Set<int> _selectedTodos = Set<int>();

  @override
  void initState() {
    super.initState();
    _fetchTodos();
  }

  Future<void> _fetchTodos() async {
    try {
      final todoData = await _apiService.fetchTodos(widget.currentIdNumber);
      setState(() {
        _todos = List<Map<String, dynamic>>.from(todoData['todos'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
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

  Future<void> _showAddTodoDialog() async {
    final TextEditingController taskController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
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
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: taskController,
              decoration: InputDecoration(
                labelText: widget.currentLanguage == 'ja' ? 'タスクを入力' : 'Enter task',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: Icon(Icons.task, color: Color(0xFF3452B4)),
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
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (value) {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop();
                  _addNewTodo(taskController.text.trim());
                }
              },
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
                  _addNewTodo(taskController.text.trim());
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
  }

  Future<void> _addNewTodo(String task) async {
    try {
      await _apiService.addTodo(widget.currentIdNumber, task);
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
      _selectedTodos.clear();
    });
  }

  void _toggleTodoSelection(int todoId) {
    setState(() {
      if (_selectedTodos.contains(todoId)) {
        _selectedTodos.remove(todoId);
      } else {
        _selectedTodos.add(todoId);
      }
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
                  if (_isDeleteMode)
                    IconButton(
                      onPressed: _toggleDeleteMode,
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
                    Text(
                      widget.currentLanguage == 'ja'
                          ? '素晴らしい！すべて完了しました'
                          : 'Great! All tasks completed',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
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

                  return GestureDetector(
                    onLongPress: () {
                      if (!_isDeleteMode) {
                        _toggleDeleteMode();
                      }
                      _toggleTodoSelection(todo['todoId']);
                    },
                    onTap: () {
                      if (_isDeleteMode) {
                        _toggleTodoSelection(todo['todoId']);
                      } else {
                        _updateTodoStatus(todo['todoId'], isCompleted ? 0 : 1);
                      }
                    },
                    child: Container(
                      margin: EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.red.shade100
                            : isCompleted
                            ? Colors.green.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.red
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
                        leading: _isDeleteMode
                            ? Checkbox(
                          value: isSelected,
                          onChanged: (bool? value) {
                            _toggleTodoSelection(todo['todoId']);
                          },
                          activeColor: Colors.red,
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
                          child: Row(
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
                              if (!_isDeleteMode)
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
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: _isDeleteMode
                    ? Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _toggleDeleteMode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          widget.currentLanguage == 'ja' ? 'キャンセル' : 'CANCEL',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _deleteSelectedTodos,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          widget.currentLanguage == 'ja' ? '削除' : 'DELETE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
                    : ElevatedButton.icon(
                  onPressed: () => _showAddTodoDialog(),
                  icon: Icon(Icons.add, color: Colors.white),
                  label: Text(
                    widget.currentLanguage == 'ja' ? 'タスクを追加' : 'Add Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF3452B4),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}