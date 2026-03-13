import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/constants/app_enums.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/core/utils/formatters.dart';
import 'package:top_quality/domain/entities/app_user.dart';
import 'package:top_quality/domain/entities/employee_draft.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/common_widgets.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final canView =
        currentUser?.hasPermission(AppPermission.usersView) ?? false;
    if (!canView) {
      return EmptyPlaceholder(
        title: context.t(en: 'Restricted area', ar: 'منطقة مقيدة'),
        subtitle: context.t(
          en: 'You do not have permission to access employee management.',
          ar: 'ليس لديك صلاحية للوصول إلى إدارة الموظفين.',
        ),
        icon: Icons.lock_outline,
      );
    }

    final canCreate =
        currentUser?.hasPermission(AppPermission.usersCreate) ?? false;
    final canEdit =
        currentUser?.hasPermission(AppPermission.usersEdit) ?? false;
    final canDelete =
        currentUser?.hasPermission(AppPermission.usersDelete) ?? false;
    final canAssign =
        currentUser?.hasPermission(AppPermission.usersAssignPermissions) ??
        false;

    final usersValue = ref.watch(usersProvider);

    return usersValue.when(
      data: (users) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (canCreate)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _openEmployeeDialog(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    context.t(en: 'Create Employee', ar: 'إنشاء موظف'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ...users.map(
              (user) => _UserCard(
                user: user,
                canEdit: canEdit,
                canDelete: canDelete,
                onEdit: () => _openEmployeeDialog(context, ref, user: user),
                onToggleActive: () => _toggleActive(context, ref, user),
                onDelete: () => _deleteUser(context, ref, user.id),
              ),
            ),
            if (!canAssign)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  context.t(
                    en: 'Permission assignment is disabled for your account.',
                    ar: 'تعيين الصلاحيات غير مفعّل لهذا الحساب.',
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  Future<void> _openEmployeeDialog(
    BuildContext context,
    WidgetRef ref, {
    AppUser? user,
  }) async {
    final nameController = TextEditingController(text: user?.name ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');
    final companyController = TextEditingController();
    final passwordController = TextEditingController();
    UserRole selectedRole = user?.role ?? UserRole.orderEntry;
    final selectedPermissions = <AppPermission>{...user?.permissions ?? {}};

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            user == null
                ? context.t(en: 'Create Employee', ar: 'إنشاء موظف')
                : context.t(en: 'Edit Employee', ar: 'تعديل موظف'),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    keyboardType: TextInputType.name,
                    autofillHints: const [AutofillHints.name],
                    decoration: InputDecoration(
                      labelText: context.t(en: 'Name', ar: 'الاسم'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Email',
                        ar: 'البريد الإلكتروني',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyController,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: context.t(
                        en: 'Company name',
                        ar: 'اسم الشركة',
                      ),
                      hintText: context.t(
                        en: 'e.g., Acme Logistics',
                        ar: 'مثال: شركة النجاح المتحدة',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: user == null
                          ? context.t(en: 'Password', ar: 'كلمة المرور')
                          : context.t(
                              en: 'Password (leave blank to keep)',
                              ar: 'كلمة المرور (اتركها فارغة للإبقاء)',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    items: UserRole.values
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(context.roleLabel(role)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedRole = value ?? selectedRole),
                    decoration: InputDecoration(
                      labelText: context.t(en: 'Role', ar: 'الدور'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.t(en: 'Permissions', ar: 'الصلاحيات'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppPermission.values.map((permission) {
                      final selected = selectedPermissions.contains(permission);
                      return FilterChip(
                        label: Text(permission.code),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              selectedPermissions.add(permission);
                            } else {
                              selectedPermissions.remove(permission);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t(en: 'Cancel', ar: 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t(en: 'Save', ar: 'حفظ')),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      return;
    }

    final payload = EmployeeDraft(
      id: user?.id,
      name: nameController.text.trim(),
      email: emailController.text.trim(),
      password: passwordController.text.trim().isEmpty
          ? null
          : passwordController.text.trim(),
      companyName: companyController.text.trim().isEmpty
          ? null
          : companyController.text.trim(),
      role: selectedRole,
      permissions: selectedPermissions,
      isActive: user?.isActive ?? true,
    );

    if (user == null) {
      await ref
          .read(operationsControllerProvider.notifier)
          .createEmployee(payload);
    } else {
      await ref
          .read(operationsControllerProvider.notifier)
          .updateEmployee(payload);
    }

    if (!context.mounted) {
      return;
    }
    _showResult(context, ref);
  }
Future<void> _toggleActive(
  BuildContext context,
  WidgetRef ref,
  AppUser user,
) async {
  await ref
      .read(operationsControllerProvider.notifier)
      .deactivateEmployee(
        employeeId: user.id,
        isActive: !user.isActive,
      );

  if (!context.mounted) return;

  _showResult(context, ref);
}

Future<void> _deleteUser(
  BuildContext context,
  WidgetRef ref,
  String userId,
) async {
  await ref
      .read(operationsControllerProvider.notifier)
      .deleteEmployee(userId);

  if (!context.mounted) return;

  _showResult(context, ref);
}

void _showResult(BuildContext context, WidgetRef ref) {
  final state = ref.read(operationsControllerProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        state.hasError
            ? state.error.toString()
            : context.t(
                en: 'Employee operation completed.',
                ar: 'اكتملت عملية الموظف.',
              ),
      ),
    ),
  );
}
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final AppUser user;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final permissionsLabel =
        user.permissions.map((item) => item.code).join(', ');
    final actions = <Widget>[
      if (canEdit)
        IconButton(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          tooltip: context.t(en: 'Edit employee', ar: 'تعديل الموظف'),
        ),
      if (canEdit)
        IconButton(
          onPressed: onToggleActive,
          icon: Icon(
            user.isActive
                ? Icons.person_off_outlined
                : Icons.person_outline,
          ),
          tooltip: user.isActive
              ? context.t(en: 'Deactivate', ar: 'تعطيل')
              : context.t(en: 'Activate', ar: 'تفعيل'),
        ),
      if (canDelete)
        IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          tooltip: context.t(en: 'Delete employee', ar: 'حذف الموظف'),
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 680;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${user.email}\n${context.roleLabel(user.role)} • ${user.isActive ? context.t(en: 'Active', ar: 'نشط') : context.t(en: 'Inactive', ar: 'غير نشط')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );

            final meta = Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    '${context.t(en: 'Permissions', ar: 'الصلاحيات')}: $permissionsLabel',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  user.lastActive == null
                      ? context.t(
                          en: 'No recent activity',
                          ar: 'لا يوجد نشاط حديث',
                        )
                      : AppFormatters.shortDateTime(user.lastActive!),
                ),
              ],
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        meta,
                        if (actions.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: actions,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 12),
                meta,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: actions,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
