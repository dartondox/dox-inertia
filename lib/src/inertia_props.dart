/// A prop with a special rule. Make one with `Inertia.optional`,
/// `Inertia.defer`, `Inertia.always` or `Inertia.merge`.
abstract class InertiaProp {
  const InertiaProp(this.value);

  /// The value, or a function that gives the value.
  final Object? value;
}

/// Sent only when a partial reload asks for it by name.
class OptionalProp extends InertiaProp {
  const OptionalProp(Object? Function() super.value);
}

/// Not sent on the first visit. The page loads it right after, with a
/// partial reload. Props of the same [group] load in one request.
class DeferProp extends OptionalProp {
  const DeferProp(super.value, {this.group = 'default'});

  final String group;
}

/// Always sent, also when a partial reload does not ask for it.
class AlwaysProp extends InertiaProp {
  const AlwaysProp(super.value);
}

/// The page adds the new value to the old one (eg. the next page of a
/// list), instead of replacing it.
class MergeProp extends InertiaProp {
  const MergeProp(super.value);
}
